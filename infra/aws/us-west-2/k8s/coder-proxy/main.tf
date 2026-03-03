provider "aws" {
  region  = var.region
  profile = var.profile
}

data "aws_eks_cluster" "this" {
  name = var.cluster_name
}

data "aws_eks_cluster_auth" "this" {
  name = var.cluster_name
}

data "aws_region" "this" {}

provider "helm" {
  kubernetes = {
    host                   = data.aws_eks_cluster.this.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)
    token                  = data.aws_eks_cluster_auth.this.token
  }
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.this.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.this.token
}

data "http" "login" {
  url    = "${var.coder_access_url}/api/v2/users/login"
  method = "POST"
  request_headers = {
    Accept = "application/json"
  }
  request_body = jsonencode({
    email    = var.coder_admin_email
    password = var.coder_admin_password
  })

  retry {
    attempts     = 5
    min_delay_ms = (5 * 1000) # 5 seconds 
  }
}

provider "coderd" {
  url   = var.coder_access_url
  token = jsondecode(data.http.login.response_body).session_token
}

locals {
  azs          = slice(var.azs, 0, 1)
  pub_subs     = [for az in local.azs : "${var.vpc_name}-public-${data.aws_region.this.region}${az}"]
  release_name = "coder"
  chart_name   = "coder"
  namespace    = "coder"

  common_name           = trimprefix(trimprefix(var.coder_proxy_url, "https://"), "http://")
  wildcard_name         = trimprefix(trimprefix(var.coder_proxy_wildcard_url, "https://"), "http://")
  ssl_vol_friendly_name = replace(local.common_name, ".", "-")
}

resource "kubernetes_manifest" "certificate" {

  field_manager {
    force_conflicts = true
  }

  wait {
    condition {
      type   = "Ready"
      status = "True"
    }
  }

  timeouts {
    create = "10m"
    update = "10m"
    delete = "30s"
  }

  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind       = "Certificate"
    metadata = {
      name      = local.ssl_vol_friendly_name
      namespace = module.coder-proxy.namespace
    }
    spec = {
      commonName = local.common_name
      dnsNames = [
        local.common_name,
        local.wildcard_name
      ]
      duration    = "2160h" # 90 days
      renewBefore = "360h"  # 15 days
      issuerRef = {
        kind = "ClusterIssuer"
        name = "issuer"
      }
      secretName = local.ssl_vol_friendly_name
      privateKey = {
        rotationPolicy = "Never"
        algorithm      = "RSA"
        encoding       = "PKCS1"
        size           = "2048"
      }
    }
  }
}

resource "aws_eip" "coder" {
  count            = length(local.pub_subs)
  domain           = "vpc"
  public_ipv4_pool = "amazon"
  tags = {
    Name = "coder-eip-${count.index}"
  }
}

module "coder-proxy" {

  source = "../../../../../modules/k8s/bootstrap/coder-proxy"

  proxy = {
    access_url       = var.coder_proxy_url
    wildcard_url     = var.coder_proxy_wildcard_url
    coder_access_url = var.coder_access_url
    mount_ssl        = true
    mount_ssl_name   = kubernetes_manifest.certificate.manifest.spec.secretName
    name             = var.coder_proxy_name
    display_name     = var.coder_proxy_display_name
    icon             = var.coder_proxy_icon
    rep_cnt          = 2
    image_repo       = var.image_repo
    image_tag        = var.image_tag
  }

  namespace      = local.namespace
  resource_limit = {}
  resource_request = {
    cpu    = "500m"
    memory = "1Gi"
  }
  svc_annot = {
    "service.beta.kubernetes.io/aws-load-balancer-nlb-target-type" = "ip"
    "service.beta.kubernetes.io/aws-load-balancer-scheme"          = "internet-facing"
    "service.beta.kubernetes.io/aws-load-balancer-attributes"      = "deletion_protection.enabled=false"
    "service.beta.kubernetes.io/aws-load-balancer-eip-allocations" = join(",", aws_eip.coder.*.allocation_id)
    "service.beta.kubernetes.io/aws-load-balancer-subnets"         = join(",", local.pub_subs)
  }
  tolerations = [{
    key      = "CriticalAddonsOnly"
    operator = "Exists"
  }]
  topology_spread = [{
    max_skew           = 1
    topology_key       = "kubernetes.io/hostname"
    when_unsatisfiable = "ScheduleAnyway"
    label_selector = {
      match_labels = {
        "app.kubernetes.io/name"    = local.chart_name
        "app.kubernetes.io/part-of" = local.chart_name
      }
    }
    match_label_keys = [
      "app.kubernetes.io/instance"
    ]
  }]
  affinity = {
    nodeAffinity = {
      requiredDuringSchedulingIgnoredDuringExecution = {
        nodeSelectorTerms = [{
          matchExpressions = [{
            key      = "topology.kubernetes.io/zone"
            operator = "In"
            values   = [for az in local.azs : "${data.aws_region.this.region}${az}"]
          }]
        }]
      }
    }
    # podAntiAffinity = {
    #   preferredDuringSchedulingIgnoredDuringExecution = [{
    #     weight = 100
    #     podAffinityTerm = {
    #       topologyKey = "kubernetes.io/hostname"
    #       labelSelector = {
    #         matchLabels = {
    #           "app.kubernetes.io/instance" = local.release_name
    #           "app.kubernetes.io/name"     = local.chart_name
    #           "app.kubernetes.io/part-of"  = local.chart_name
    #         }
    #       }
    #     }
    #   }]
    # }
  }
}