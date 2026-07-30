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

provider "kubernetes" {
  host                   = data.aws_eks_cluster.this.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.this.token
}

locals {
  secrets_manager_item = sensitive(jsonencode({
    "VANTAGE_API_TOKEN" = var.vantage_api_token
  }))
}

resource "aws_secretsmanager_secret" "vantage" {
  region      = var.region
  name_prefix = "vantage-token"
}

resource "time_static" "secret_update" {
  triggers = {
    checksum = sha256(local.secrets_manager_item)
  }
}

resource "aws_secretsmanager_secret_version" "vantage" {
  region                   = var.region
  secret_id                = aws_secretsmanager_secret.vantage.id
  secret_string_wo         = local.secrets_manager_item
  secret_string_wo_version = time_static.secret_update.unix
}
resource "kubernetes_manifest" "vantage" {

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
      name        = "${var.region}.vantage"
      namespace   = "argocd"
      labels      = {}
      annotations = {}
    }
    spec = {
      project = "default"
      source = {
        repoURL        = "https://github.com/coder/ai.coder.com"
        path           = "charts/vantage"
        targetRevision = "main"
        helm = {
          releaseName = "vantage-kubernetes-agent"
          values = yamlencode({
            extra = {
              secrets = {
                annotations = {
                  "checksum/config" = sha256(local.secrets_manager_item)
                }
                refreshInterval = "1h0m0s"
                refreshPolicy   = "Periodic"
                secretArn       = aws_secretsmanager_secret.vantage.arn
              }
              secretStore = {
                aws = {
                  region = var.region
                }
              }
            }
            vantage = {
              enabled = true
              agent = {
                secret = {
                  name = "vantage-kubernetes-agent.secrets"
                  key  = "VANTAGE_API_TOKEN"
                }
                clusterID = "${var.region}.${data.aws_eks_cluster.this.id}"
              }
              persist = {
                storageClassName = "gp3-automode"
              }
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
          })
        }
      }
      destination = {
        server    = data.aws_eks_cluster.this.arn
        namespace = "vantage"
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