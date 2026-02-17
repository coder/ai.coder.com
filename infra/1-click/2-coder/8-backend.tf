## 
# Setup main provisioner + proxy if license is added.
##

##
# External Provisioner Setup
##

resource "coderd_license" "enterprise" {
  count   = var.coder_license != "" ? 1 : 0
  license = var.coder_license
}

locals {
  coder_ns           = "coder"
  coder_release_name = "coder"
  coder_svc_url      = "http://${local.coder_release_name}.${local.coder_ns}.svc.cluster.local"
}

module "coder-ext-prov" {

  count  = length(coderd_license.enterprise)
  depends_on = [ coderd_license.enterprise ]
  source = "../../../modules/k8s/bootstrap/coder-provisioner"

  release_name  = "coder-provisioner"
  namespace     = "coder-provisioner"
  chart_name    = "coder-provisioner"
  chart_version = var.coder_version

  cluster_name              = "${local.formatted_name}"
  cluster_oidc_provider_arn = data.aws_iam_openid_connect_provider.coder.arn

  coder = {
    access_url = local.coder_svc_url
    ws_ns      = [local.coder_ns]
    image_tag  = "v${var.coder_version}"
    rep_cnt    = 5
  }
}

##
# Proxy Setup
##

locals {
  apex_domain        = join(".", slice(split(".", var.domain_name), length(split(".", var.domain_name)) - 2, length(split(".", var.domain_name))))
  pub_subs           = [for az in var.azs : "${local.formatted_name}-public-${data.aws_region.this.region}${az}"]
  proxy_access_url   = "proxy.${var.domain_name}"
  proxy_wildcard_url = "*.proxy.${var.domain_name}"
}

##
# Fetch AWS Hosted Zone
##

data "aws_route53_zone" "coder" {
  name = local.apex_domain
}

resource "aws_eip" "proxy" {
  count = 1
  domain           = "vpc"
  public_ipv4_pool = "amazon"
  tags = {
    Name = "${local.formatted_name}-proxy-${count.index}"
  }
}

resource "aws_route53_record" "proxy-primary" {
  name    = local.proxy_access_url
  records = aws_eip.proxy.*.public_ip
  ttl     = 60
  type    = "A"
  zone_id = data.aws_route53_zone.coder.zone_id
}

resource "aws_route53_record" "proxy-wildcard" {
  name    = local.proxy_wildcard_url
  records = aws_eip.proxy.*.public_ip
  ttl     = 60
  type    = "A"
  zone_id = data.aws_route53_zone.coder.zone_id
}

resource "aws_acm_certificate" "proxy" {
  domain_name               = local.proxy_access_url
  subject_alternative_names = [local.proxy_wildcard_url]
  validation_method         = "DNS"
}

resource "aws_route53_record" "proxy_validation" {

  for_each = {
    for rec in aws_acm_certificate.proxy.domain_validation_options : rec.domain_name => {
      name   = rec.resource_record_name
      record = rec.resource_record_value
      type   = rec.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = data.aws_route53_zone.coder.zone_id
}

resource "aws_acm_certificate_validation" "proxy" {
  certificate_arn         = aws_acm_certificate.proxy.arn
  validation_record_fqdns = [for record in aws_route53_record.proxy_validation : record.fqdn]

  timeouts {
    create = "30m"
  }
}

# module "coder-proxy" {

#   count  = length(coderd_license.enterprise)
#   depends_on = [ coderd_license.enterprise, module.coder-ext-prov ]
#   source = "../../../modules/k8s/bootstrap/coder-proxy"

#   release_name  = "coder-proxy"
#   namespace     = "coder-proxy"
#   chart_name    = "coder"
#   chart_version = var.coder_version

#   proxy = {
#     name = "proxy"
#     display_name = "Coder Proxy" 
#     access_url       = "https://${local.proxy_access_url}"
#     icon = "/emojis/1f4a1.png" # 💡
#     wildcard_url     = local.proxy_wildcard_url
#     coder_access_url = "https://${var.domain_name}"
#     image_tag        = "v${var.coder_version}"
#     rep_cnt          = 1
#   }

#   svc_annot = {
#     "service.beta.kubernetes.io/aws-load-balancer-nlb-target-type" = "instance"
#     "service.beta.kubernetes.io/aws-load-balancer-scheme"          = "internet-facing"
#     "service.beta.kubernetes.io/aws-load-balancer-attributes"      = "deletion_protection.enabled=false"
#     "service.beta.kubernetes.io/aws-load-balancer-eip-allocations" = join(",", aws_eip.proxy.*.allocation_id)
#     "service.beta.kubernetes.io/aws-load-balancer-subnets"         = join(",", [local.pub_subs[0]])
#     "service.beta.kubernetes.io/aws-load-balancer-ssl-cert"        = aws_acm_certificate.proxy.arn
#     "service.beta.kubernetes.io/aws-load-balancer-ssl-ports"       = 443
#   }
# }