# Wait for DNS propagation. May require multiple requests

data "http" "first-user" {

  depends_on = [module.coder-server]

  url    = "http://${aws_eip.coder.0.public_ip}/api/v2/users/first"
  method = "POST"
  request_headers = {
    Host   = var.domain_name
    Accept = "application/json"
  }
  request_body = jsonencode({
    email    = var.coder_admin_email
    username = var.coder_admin_username
    password = var.coder_admin_password
    trial    = false
  })
  retry {
    attempts     = 60 + 1
    max_delay_ms = 5000
    min_delay_ms = 5000
  }
}

locals {
  coder_svc_url = "http://${local.coder_release_name}.${local.coder_ns}.svc.cluster.local"
}

module "coder-kube-logstream" {

  depends_on = [module.coder-server]
  source     = "../../../modules/k8s/bootstrap/coder-logstream"

  coder = {
    access_url = local.coder_svc_url
    ws_ns      = [local.coder_ns]
  }
}

module "monitoring" {

  source = "../../../modules/k8s/bootstrap/monitoring"

  chart_version             = "0.7.0-rc.1"
  chart_timeout             = 360
  cluster_name              = "${var.name}-${local.normalized_domain_name}"
  cluster_oidc_provider_arn = data.aws_iam_openid_connect_provider.coder.arn

  lb_class      = "service.k8s.aws/nlb"
  storage_class = kubernetes_manifest.automode-sc.manifest.metadata.name

  domain_name = "grafana.${var.domain_name}"
  tolerations = concat([{
    key      = "CriticalAddonsOnly"
    operator = "Exists"
    }], [for toleration in kubernetes_manifest.nodepool["karpenter"].manifest.spec.template.spec.taints : {
    key      = toleration.key
    operator = "Equal"
    value    = toleration.value
    effect   = toleration.effect
  }])

  coder = {
    db = {
      host     = data.aws_db_instance.coder.address
      password = var.coder_password
      username = var.coder_username
      database = data.aws_db_instance.coder.db_name
    }
    selector = {
      coderd        = "pod=~`coder.*`, pod!~`.*provisioner.*`, namespace=~`(coder)`"
      provisionerd  = "pod=~`coder-provisioner.*`, namespace=~`(coder)`"
      workspaces    = "pod!~`coder.*`, namespace=~`(coder)`"
      ctrl_plane_ns = "coder"
      ext_prov_ns   = "coder"
    }
  }
  grafana = {
    admin = {
      username = var.grafana_admin_username
      password = var.grafana_admin_password
    }
    db = {
      host     = data.aws_db_instance.grafana.address
      password = var.grafana_password
      username = var.grafana_username
      database = data.aws_db_instance.grafana.db_name
    }
    svc = {
      annots = {
        "service.beta.kubernetes.io/aws-load-balancer-nlb-target-type"      = "instance"
        "service.beta.kubernetes.io/aws-load-balancer-scheme"               = "internet-facing"
        "service.beta.kubernetes.io/aws-load-balancer-attributes"           = "deletion_protection.enabled=false"
        "service.beta.kubernetes.io/aws-load-balancer-healthcheck-protocol" = "tcp"
        "service.beta.kubernetes.io/aws-load-balancer-healthcheck-path"     = "/api/health"
        "service.beta.kubernetes.io/aws-load-balancer-ssl-cert"             = aws_acm_certificate.grafana.arn
        "service.beta.kubernetes.io/aws-load-balancer-ssl-ports"            = 443
        "service.beta.kubernetes.io/aws-load-balancer-eip-allocations"      = join(",", aws_eip.grafana.*.allocation_id)
        "service.beta.kubernetes.io/aws-load-balancer-subnets"              = join(",", [local.pub_subs[0]])
      }
    }
  }
  loki = {
    s3 = {
      chunks_bucket = data.aws_s3_bucket.loki.id
      ruler_bucket  = data.aws_s3_bucket.loki.id
      region        = data.aws_s3_bucket.loki.bucket_region
    }
  }
}