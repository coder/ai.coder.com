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
  source      = "../../../security/policy"
  name        = "crt-mgr"
  path         = "/${var.cluster_name}/${var.region}/"
  description = "Cert-Manager for R53 Policy"
  policy_json = data.aws_iam_policy_document.route53.json
}

module "oidc-role" {
  source       = "../../../security/role/access-entry"
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

resource "kubernetes_secret_v1" "cloudflare" {
  metadata {
    name      = "cloudflare-token"
    namespace = kubernetes_namespace_v1.cert-manager.metadata[0].name
    annotations = {
      "custom.kubernetes.secret/key"   = "key"
      "custom.kubernetes.secret/email" = var.cloudflare_email
    }
  }
  data = {
    key = var.cloudflare_api_token
  }
}

resource "kubernetes_manifest" "cert-manager" {

  wait {
    fields = {
      "status.health.status" = "Healthy"
      "statys.sync.status" = "Synced"
    }
  }

  wait {
    create = "5m"
    update = "5m"
    delete = "30s"
  }

  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind = "Application"
    metadata = {
      name = "cert-manager"
      namespace = "argocd"
      labels = {}
      annotations = {}
      finalizers = [
        "resources-finalizer.argocd.argoproj.io"
      ]
    }
    spec = {
      project = "default"
      source = {
        repoURL = "oci://quay.io/jetstack/charts"
        chart = "cert-manager"
        targetRevision = "v1.18.2"
        helm = {
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
                name = "issuer"
                acme = {
                  privateKeySecretRef = "issuer-account-key"
                  cloudflare = {
                    apiTokenSecretRef = {
                      name = kubernetes_secret_v1.cf.metadata[0].name
                      key = kubernetes_secret_v1.cf.metadata[0].annotations["custom.kubernetes.secret/key"]
                    }
                    email = kubernetes_secret_v1.cf.metadata[0].annotations["custom.kubernetes.secret/email"]
                  }
                }
              }
            }
            cert-manager = {
              crds = {
                enabled = true
              }
              nodeSelector = {}
              tolerations = local.tolerations
              affinity = local.affinity
              webhook = {
                tolerations = local.tolerations
                affinity = local.affinity
              }
              cainjector = {
                tolerations = local.tolerations
                affinity = local.affinity
              }
              startupapicheck = {
                tolerations = local.tolerations
                affinity = local.affinity
              }
            }
          })
        }
      }
      destination = {
        server = data.aws_eks_cluster.this.arn
        namespace = kubernetes_namespace_v1.cert-manager.metadata[0].name
      }
      syncPolicy = {
        syncOptions = [
          "CreateNamespace=false",
          "Delete=false"
        ]
      }
    }
  }
}