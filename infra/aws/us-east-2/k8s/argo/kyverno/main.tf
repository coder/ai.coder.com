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

resource "kubernetes_manifest" "kyverno" {

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
      name        = "${var.region}.kyverno"
      namespace   = "argocd"
      labels      = {}
      annotations = {}
    }
    spec = {
      project = "default"
      source = {
        repoURL        = "https://kyverno.github.io/kyverno/"
        chart          = "kyverno"
        targetRevision = "3.7.1"
        helm = {
          releaseName = "kyverno"
          values = yamlencode({

            global = {
              tolerations = [{
                effect   = "NoSchedule"
                key      = "CriticalAddonsOnly"
                operator = "Exists"
              }]
            }

            config = {
              defaultRegistry               = "docker.io"
              enableDefaultRegistryMutation = true
              webhooks = {
                namespacesSelector = {
                  matchExpressions = [{
                    key      = "kubernetes.io/metadata.name"
                    operator = "NotIn"
                    values = [
                      "kube-system",
                    ]
                  }]
                }
              }
            }

            crds = {
              migration = {
                nodeAffinity = local.nodeAffinity
              }
            }
            admissionController = {
              replicas     = 3
              nodeAffinity = local.nodeAffinity
            }
            backgroundController = {
              replicas     = 2
              nodeAffinity = local.nodeAffinity
            }
            cleanupController = {
              replicas     = 2
              nodeAffinity = local.nodeAffinity
            }
            reportsController = {
              replicas     = 2
              nodeAffinity = local.nodeAffinity
            }
          })
        }
      }
      destination = {
        server    = data.aws_eks_cluster.this.arn
        namespace = "kyverno"
      }
      syncPolicy = {
        syncOptions = [
          "CreateNamespace=true",
          "Delete=false",
          "ServerSideApply=true" # Avoid error here: https://github.com/argoproj/argo-cd/issues/11269
        ]
      }
    }
  }
}