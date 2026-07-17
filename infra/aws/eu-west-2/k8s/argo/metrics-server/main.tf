provider "aws" {
  region  = var.region
  profile = var.profile
}

data "aws_eks_cluster" "controller" {
  region = "us-east-2"
  name   = var.cluster_name
}

data "aws_eks_cluster_auth" "controller" {
  region = "us-east-2"
  name   = var.cluster_name
}

data "aws_eks_cluster" "this" {
  name = var.cluster_name
}

data "aws_eks_cluster_auth" "this" {
  name = var.cluster_name
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.controller.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.controller.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.controller.token
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
      name        = "${var.region}.metrics-server"
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
          releaseName = "metrics-server"
          values = yamlencode({
            nodeSelector = {}
            tolerations = [{
              key      = "CriticalAddonsOnly"
              operator = "Exists"
            }]
            affinity = {}
          })
        }
      }
      destination = {
        server    = data.aws_eks_cluster.this.arn
        namespace = "kube-system"
      }
      syncPolicy = {
        syncOptions = [
          "CreateNamespace=false",
          "Delete=confirm"
        ]
      }
    }
  }
}