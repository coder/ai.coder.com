##
# Fetch DNS Zone
##

data "aws_route53_zone" "coder" {
  name = local.apex_domain
}

##
# SSL Certificate
##

resource "aws_acm_certificate" "coder" {
  domain_name               = var.domain_name
  subject_alternative_names = ["*.${var.domain_name}"]
  validation_method         = "DNS"
}

resource "aws_route53_record" "coder_validation" {

  for_each = {
    for rec in aws_acm_certificate.coder.domain_validation_options : rec.domain_name => {
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

resource "aws_acm_certificate_validation" "coder" {
  certificate_arn         = aws_acm_certificate.coder.arn
  validation_record_fqdns = [for record in aws_route53_record.coder_validation : record.fqdn]

  timeouts {
    create = "30m"
  }
}

resource "aws_acm_certificate" "grafana" {
  domain_name               = "grafana.${var.domain_name}"
  subject_alternative_names = ["*.grafana.${var.domain_name}"]
  validation_method         = "DNS"
}

resource "aws_route53_record" "grafana_validation" {

  for_each = {
    for rec in aws_acm_certificate.grafana.domain_validation_options : rec.domain_name => {
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

resource "aws_acm_certificate_validation" "grafana" {
  certificate_arn         = aws_acm_certificate.grafana.arn
  validation_record_fqdns = [for record in aws_route53_record.grafana_validation : record.fqdn]

  timeouts {
    create = "30m"
  }
}

##
# ------
##

resource "aws_iam_user" "bedrock" {
  name = "bedrock-access"
  path = "/${local.normalized_domain_name}/${data.aws_region.this.region}/"
}

resource "aws_iam_access_key" "bedrock" {
  user = aws_iam_user.bedrock.name
}

resource "aws_iam_user_policy_attachment" "bedrock" {
  user = aws_iam_user.bedrock.name
  # https://docs.aws.amazon.com/aws-managed-policy/latest/reference/AmazonBedrockLimitedAccess.html
  policy_arn = "arn:aws:iam::aws:policy/AmazonBedrockLimitedAccess"
}

locals {
  pub_subs = [for az in var.azs : "${local.formatted_name}-public-${data.aws_region.this.region}${az}"]
}

##
# EIP Mapping
##

resource "aws_eip" "coder" {
  count            = length(var.azs)
  domain           = "vpc"
  public_ipv4_pool = "amazon"
  tags = {
    Name = "${local.formatted_name}-coder-${count.index}"
  }
}

resource "aws_eip" "grafana" {
  count            = 1
  domain           = "vpc"
  public_ipv4_pool = "amazon"
  tags = {
    Name = "${local.formatted_name}-grafana-${count.index}"
  }
}

resource "aws_route53_record" "coder-primary" {
  name    = var.domain_name
  records = aws_eip.coder.*.public_ip
  ttl     = 60
  type    = "A"
  zone_id = data.aws_route53_zone.coder.zone_id
}

resource "aws_route53_record" "coder-wildcard" {
  name    = "*.${var.domain_name}"
  records = aws_eip.coder.*.public_ip
  ttl     = 60
  type    = "A"
  zone_id = data.aws_route53_zone.coder.zone_id
}

resource "aws_route53_record" "grafana-primary" {
  name    = "grafana.${var.domain_name}"
  records = aws_eip.grafana.*.public_ip
  ttl     = 60
  type    = "A"
  zone_id = data.aws_route53_zone.coder.zone_id
}

resource "aws_route53_record" "grafana-wildcard" {
  name    = "*.grafana.${var.domain_name}"
  records = aws_eip.grafana.*.public_ip
  ttl     = 60
  type    = "A"
  zone_id = data.aws_route53_zone.coder.zone_id
}

##
# Helm Installs
##

locals {
  coder_release_name = "coder"
  coder_ns           = "coder"
}

module "coder-server" {

  source = "../../../modules/k8s/bootstrap/coder-server"

  release_name              = local.coder_release_name
  chart_version             = var.coder_version
  cluster_name              = data.aws_eks_cluster.coder.id
  cluster_oidc_provider_arn = data.aws_iam_openid_connect_provider.coder.arn

  namespace = local.coder_ns
  # lb_class = "eks.amazonaws.com/nlb"
  lb_class = "service.k8s.aws/nlb"

  coder = {
    access_url   = "https://${var.domain_name}"
    wildcard_url = "*.${var.domain_name}"
    image_repo   = "ghcr.io/coder/coder"
    image_tag    = "v${var.coder_version}"
    rep_cnt      = 1
    # External Provisioners will be used
    prov_rep_cnt = var.coder_license != "" ? 0 : 5
  }

  prometheus = {
    enable = true
  }

  db = {
    url      = data.aws_db_instance.coder.endpoint
    username = var.coder_username
    password = var.coder_password
  }

  aibridge = {
    enabled = var.coder_license != ""
    bedrock = var.coder_license != "" ? {
      region    = data.aws_region.this.region
      model     = "global.anthropic.claude-opus-4-5-20251101-v1:0"
      access_id = aws_iam_access_key.bedrock.id
      secret_id = aws_iam_access_key.bedrock.secret
    } : null
  }

  resource_request = {
    cpu    = "1000m"
    memory = "2Gi"
  }
  resource_limit = {
    cpu    = "1000m"
    memory = "2Gi"
  }

  tags = {}

  svc_annot = {
    "service.beta.kubernetes.io/aws-load-balancer-nlb-target-type" = "instance"
    "service.beta.kubernetes.io/aws-load-balancer-scheme"          = "internet-facing"
    "service.beta.kubernetes.io/aws-load-balancer-attributes"      = "deletion_protection.enabled=false"
    "service.beta.kubernetes.io/aws-load-balancer-eip-allocations" = join(",", aws_eip.coder.*.allocation_id)
    "service.beta.kubernetes.io/aws-load-balancer-subnets"         = join(",", local.pub_subs)
    "service.beta.kubernetes.io/aws-load-balancer-ssl-cert"        = aws_acm_certificate.coder.arn
    "service.beta.kubernetes.io/aws-load-balancer-ssl-ports"       = 443
  }

  node_selector = kubernetes_manifest.nodepool["karpenter"].manifest.spec.template.metadata.labels
  tolerations = [for toleration in kubernetes_manifest.nodepool["karpenter"].manifest.spec.template.spec.taints : {
    key      = toleration.key
    operator = "Equal"
    value    = toleration.value
    effect   = toleration.effect
  }]

  topology_spread = [{
    max_skew           = 1
    topology_key       = "kubernetes.io/hostname"
    when_unsatisfiable = "ScheduleAnyway"
    label_selector = {
      match_labels = {
        "app.kubernetes.io/name"    = local.coder_release_name
        "app.kubernetes.io/part-of" = "coder"
      }
    }
    match_label_keys = [
      "app.kubernetes.io/instance"
    ]
  }]

  affinity = {
    podAntiAffinity = {
      preferredDuringSchedulingIgnoredDuringExecution = [{
        weight = 100
        podAffinityTerm = {
          labelSelector = {
            matchLabels = {
              "app.kubernetes.io/instance" = "coder"
              "app.kubernetes.io/name"     = local.coder_release_name
              "app.kubernetes.io/part-of"  = "coder"
            }
          }
          topologyKey = "kubernetes.io/hostname"
        }
      }]
    }
  }
}