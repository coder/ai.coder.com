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

resource "kubernetes_manifest" "metrics-server" {

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
      name        = "metrics-server"
      namespace   = "argocd"
      labels      = {}
      annotations = {}
      finalizers = [
        "resources-finalizer.argocd.argoproj.io"
      ]
    }
    spec = {
      project = "default"
      source = {
        repoURL        = "https://kubernetes-sigs.github.io/metrics-server/"
        chart          = "metrics-server"
        targetRevision = "3.13.0"
        helm = {
          values = yamlencode({
            nodeSelector = {}
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
          })
        }
      }
      destination = {
        server = data.aws_eks_cluster.this.arn
        # namespace = kubernetes_namespace_v1.metrics-server.metadata[0].name
        namespace = "kube-system"
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