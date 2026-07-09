provider "aws" {
  region  = var.region
  profile = var.profile
}

data "aws_region" "this" {}

data "aws_eks_cluster" "this" {
  name = var.cluster_name
}

data "aws_eks_cluster_auth" "this" {
  name = var.cluster_name
}

data "aws_iam_openid_connect_provider" "this" {
  url = data.aws_eks_cluster.this.identity[0].oidc[0].issuer
}

data "aws_db_instance" "coder" {
  db_instance_identifier = var.coder_db_rds_name
}

data "aws_vpc" "this" {
  tags = {
    Name = var.vpc_name
  }
}

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

locals {
  common_name           = trimprefix(trimprefix(var.coder_access_url, "https://"), "http://")
  wildcard_name         = trimprefix(trimprefix(var.coder_wildcard_access_url, "https://"), "http://")
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
      namespace = module.coder-server.namespace
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

locals {
  azs          = var.azs
  pub_subs     = [for az in local.azs : "${var.vpc_name}-public-${data.aws_region.this.region}${az}"]
  release_name = "coder"
  chart_name   = "coder"
  namespace    = "coder"
}

resource "aws_eip" "coder" {
  count            = length(local.pub_subs)
  domain           = "vpc"
  public_ipv4_pool = "amazon"
  tags = {
    Name = "coder-eip-${count.index}"
  }
}

# resource "kubernetes_pod_disruption_budget_v1" "coder" {
#   metadata {
#     name      = local.release_name
#     namespace = module.coder-server.namespace
#   }
#   spec {
#     # Avoid disrupting ongoing connections.
#     max_unavailable = 1
#     selector {
#       match_labels = {
#         "app.kubernetes.io/instance" = local.release_name
#         "app.kubernetes.io/name"     = local.chart_name
#         "app.kubernetes.io/part-of"  = local.chart_name
#       }
#     }
#   }
# }

# ---

resource "aws_iam_user" "bedrock" {
  name          = "${local.release_name}-bedrock"
  path          = "/${var.cluster_name}/${var.region}/"
  force_destroy = true

  tags = {
    Purpose   = "coder-aibridge"
    ManagedBy = "terraform"
  }
}

data "aws_iam_policy_document" "bedrock" {
  statement {
    sid    = "InvokeBedrockModels"
    effect = "Allow"

    actions = [
      "bedrock:InvokeModel",
      "bedrock:InvokeModelWithResponseStream"
    ]

    resources = [
      "arn:aws:bedrock:*::foundation-model/*",
      "arn:aws:bedrock:*:*:inference-profile/*"
    ]
  }
}

resource "aws_iam_policy" "bedrock" {
  name        = "${local.release_name}-bedrock"
  description = "Allow Coder AI Bridge to invoke Amazon Bedrock models."
  policy      = data.aws_iam_policy_document.bedrock.json
}

resource "aws_iam_user_policy_attachment" "bedrock" {
  user       = aws_iam_user.bedrock.name
  policy_arn = aws_iam_policy.bedrock.arn
}

resource "aws_iam_access_key" "bedrock" {
  user = aws_iam_user.bedrock.name
}

# ---

module "coder-server" {

  source = "../../../../../modules/k8s/bootstrap/coder-server"

  release_name              = local.release_name
  chart_version             = var.addon_version
  chart_name                = local.chart_name
  cluster_name              = data.aws_eks_cluster.this.id
  cluster_oidc_provider_arn = data.aws_iam_openid_connect_provider.this.arn

  coder = {
    access_url     = var.coder_access_url
    wildcard_url   = var.coder_wildcard_access_url
    mount_ssl      = true
    mount_ssl_name = kubernetes_manifest.certificate.manifest.spec.secretName

    image_repo = var.image_repo
    image_tag  = var.image_tag

    rep_cnt = length(local.pub_subs)
    # External Provisioners will be used
    prov_rep_cnt = var.coder_builtin_provisioner_count
    env_vars = {
      CODER_EXPERIMENTS = join(",", var.coder_experiments)
    }
  }

  db = {
    url      = data.aws_db_instance.coder.endpoint
    username = var.coder_db_username
    password = var.coder_db_password
    db       = var.coder_db_name
    pg_auth  = "awsiamrds"
  }

  prometheus = {
    enable = true
  }

  oidc = {
    enable        = true
    sign_in_text  = var.oidc_sign_in_text
    icon_url      = var.oidc_icon_url
    scopes        = var.oidc_scopes
    email_domain  = var.oidc_email_domain
    issuer_url    = var.coder_oidc_secret_issuer_url
    client_id     = var.coder_oidc_secret_client_id
    client_secret = var.coder_oidc_secret_client_secret
  }

  oauth2 = {
    enable                  = true
    default_provider_enable = false
    allow_signups           = true
    device_flow             = false
    allowed_orgs            = var.coder_github_allowed_orgs
    client_id               = var.coder_oauth_secret_client_id
    client_secret           = var.coder_oauth_secret_client_secret
    use_extern_auth         = false
  }

  extern_auth = [{
    id            = "primary-github"
    type          = "github"
    client_id     = var.coder_github_external_auth_secret_client_id
    client_secret = var.coder_github_external_auth_secret_client_secret
  }]

  aibridge = {
    enabled = true
  }

  namespace      = local.namespace
  resource_limit = {
    cpu    = "2"
    memory = "2Gi"
  }
  resource_request = {
    cpu    = "500m"
    memory = "2Gi"
  }
  lb_class = "service.k8s.aws/nlb"
  svc_annot = {
    "service.beta.kubernetes.io/aws-load-balancer-nlb-target-type" = "ip"
    "service.beta.kubernetes.io/aws-load-balancer-scheme"          = "internet-facing"
    "service.beta.kubernetes.io/aws-load-balancer-attributes"      = "deletion_protection.enabled=false,load_balancing.cross_zone.enabled=true"
    "service.beta.kubernetes.io/aws-load-balancer-eip-allocations" = join(",", aws_eip.coder.*.allocation_id)
    "service.beta.kubernetes.io/aws-load-balancer-subnets"         = join(",", local.pub_subs)
  }
  tolerations = [{
    key    = "platform"
    value  = "coder-server"
    effect = "NoSchedule"
  }]
  topology_spread = []
  # topology_spread = [{
  #   max_skew           = 1
  #   topology_key       = "topology.kubernetes.io/zone"
  #   when_unsatisfiable = "ScheduleAnyway"
  #   label_selector = {
  #     match_labels = {
  #       "app.kubernetes.io/name"    = local.chart_name
  #       "app.kubernetes.io/part-of" = local.chart_name
  #     }
  #   }
  #   match_label_keys = [
  #     "app.kubernetes.io/instance"
  #   ]
  # }]
  affinity = {
    nodeAffinity = {
      requiredDuringSchedulingIgnoredDuringExecution = {
        nodeSelectorTerms = [{
          matchExpressions = [
            {
              key      = "topology.kubernetes.io/zone"
              operator = "In"
              values   = [for az in local.azs : "${data.aws_region.this.region}${az}"]
            },
            {
              key      = "node.coder.io/used-for",
              operator = "In",
              values   = ["coder-server"]
            }
          ]
        }]
      }
    }
    podAntiAffinity = {
      preferredDuringSchedulingIgnoredDuringExecution = []
      requiredDuringSchedulingIgnoredDuringExecution = []
      # requiredDuringSchedulingIgnoredDuringExecution = [{
      #   labelSelector = {
      #     matchExpressions = [{
      #       key = "app.kubernetes.io/instance"
      #       operator = "In"
      #       values = [local.chart_name]
      #     }]
      #   }
      #   topologyKey = "kubernetes.io/hostname"
      # }]
    }
  }
}