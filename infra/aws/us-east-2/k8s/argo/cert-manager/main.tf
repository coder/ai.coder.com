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

data "aws_iam_openid_connect_provider" "this" {
  url = data.aws_eks_cluster.this.identity[0].oidc[0].issuer
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.this.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.this.token
}

locals {
  tolerations = [{
    key      = "CriticalAddonsOnly"
    operator = "Exists"
  }]
  affinity = {
    nodeAffinity = {
      requiredDuringSchedulingIgnoredDuringExecution = {
        nodeSelectorTerms = [{
          matchExpressions = [{
            key      = "karpenter.sh/nodepool"
            operator = "In"
            values   = ["system"]
          }]
        }]
      }
    }
  }
}

module "policy" {
  source      = "../../../../../../modules/security/policy"
  name        = "crt-mgr"
  path        = "/${var.cluster_name}/${var.region}/"
  description = "Cert-Manager for R53 Policy"
  policy_json = data.aws_iam_policy_document.route53.json
}

module "oidc-role" {
  source       = "../../../../../../modules/security/role/access-entry"
  name         = "crt-mgr"
  path         = "/${var.cluster_name}/${var.region}/"
  cluster_name = var.cluster_name
  policy_arns = {
    "CertManagerR53" = module.policy.policy_arn
  }
  cluster_policy_arns = {
    "AmazonEKSClusterAdminPolicy" = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy",
  }
  oidc_principals = {
    "${data.aws_iam_openid_connect_provider.this.arn}" = ["system:serviceaccount:*:*"]
  }
  tags = {}
}

resource "kubernetes_namespace_v1" "cert-manager" {
  metadata {
    name = "cert-manager"
  }
}

resource "aws_secretsmanager_secret" "cloudflare" {
  region      = var.region
  name_prefix = "cloudflare-token"
}

locals {
  api_token_secret_ref_key = "key"
  secrets_manager_item = sensitive(jsonencode({
    (local.api_token_secret_ref_key) = var.cloudflare_api_token
  }))
}

resource "time_static" "secret_update" {
  triggers = {
    checksum = sha256(local.secrets_manager_item)
  }
}

resource "aws_secretsmanager_secret_version" "cloudflare" {
  region                   = var.region
  secret_id                = aws_secretsmanager_secret.cloudflare.id
  secret_string_wo         = local.secrets_manager_item
  secret_string_wo_version = time_static.secret_update.unix
}

resource "kubernetes_manifest" "cert-manager" {

  wait {
    fields = {
      "status.health.status" = "Healthy"
      "status.sync.status"   = "Synced"
    }
  }

  timeouts {
    create = "5m"
    update = "5m"
    delete = "30s"
  }

  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name        = "${var.region}.cert-manager"
      namespace   = "argocd"
      labels      = {}
      annotations = {}
    }
    spec = {
      project = "default"
      source = {
        repoURL        = "https://github.com/coder/ai.coder.com"
        path           = "charts/cert-manager"
        targetRevision = "main"
        helm = {
          releaseName = "cert-manager"
          values = yamlencode({
            extra = {
              r53 = {
                sa = {
                  enable = true
                  annotations = {
                    "eks.amazonaws.com/role-arn" = module.oidc-role.role_arn
                  }
                }
                role = {
                  enable = true
                }
                rolebinding = {
                  enable = true
                }
              }
              defaultIssuer = {
                enable = true
                name   = "issuer"
                acme = {
                  privateKeySecretRef = {
                    name = "issuer-account-key"
                  }
                  cloudflare = {
                    apiTokenSecretRef = {
                      secretArn = aws_secretsmanager_secret.cloudflare.arn
                      key       = local.api_token_secret_ref_key
                    }
                    email = var.cloudflare_email
                  }
                }
              }
              secretStore = {
                aws = {
                  region = var.region
                }
              }
            }
            cert-manager = {
              crds = {
                enabled = true
              }
              nodeSelector = {}
              tolerations  = local.tolerations
              affinity     = local.affinity
              webhook = {
                tolerations = local.tolerations
                affinity    = local.affinity
              }
              cainjector = {
                tolerations = local.tolerations
                affinity    = local.affinity
              }
              startupapicheck = {
                tolerations = local.tolerations
                affinity    = local.affinity
              }
            }
          })
        }
      }
      destination = {
        server    = data.aws_eks_cluster.this.arn
        namespace = "cert-manager"
      }
      syncPolicy = {
        syncOptions = [
          "CreateNamespace=true",
          "Delete=false"
        ]
      }
    }
  }
}