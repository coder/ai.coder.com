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
  common_name           = "grafana.ai.coder.com"
  ssl_vol_friendly_name = replace(local.common_name, ".", "-")
}

resource "kubernetes_manifest" "cloudfront-grafana" {

  wait {
    fields = {
      "status.health.status" = "Healthy"
    }
  }

  timeouts {
    create = "30m" # Wait for cert-manager.io/v1/certificate to stabilize
    update = "5m"
    delete = "30s"
  }

  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name        = "${var.region}.cloudfront-grafana"
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
        repoURL        = "https://github.com/coder/ai.coder.com"
        path           = "charts/cloudfront"
        targetRevision = "main"
        helm = {
          releaseName = "cloudfront-grafana"
          values = yamlencode({
            extra = {
              cloudfront = {
                annotations = {
                  "services.k8s.aws/adopted" = "true"
                  "services.k8s.aws/adoption-fields" = jsonencode({
                    id = "E2A95S8B9B7ZE2"
                  })
                  "services.k8s.aws/adoption-policy" = "adopt-or-create"
                }
                originId     = "ALB-Grafana"
                domainName   = local.common_name
                lbDomainName = trimprefix(trimprefix(var.grafana_endpoint, "https://"), "http://")
                comment      = "CloudFront Distribution for the AWS Managed Grafana Service."
              }
              certificate = {
                name       = local.ssl_vol_friendly_name
                commonName = local.common_name
                dnsNames   = ["${local.common_name}", "*.${local.common_name}"]
                annotations = {
                  "services.k8s.aws/region" = "us-east-1"
                }
              }
            }
          })
        }
      }
      destination = {
        server    = data.aws_eks_cluster.this.arn
        namespace = "cloudfront-grafana"
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