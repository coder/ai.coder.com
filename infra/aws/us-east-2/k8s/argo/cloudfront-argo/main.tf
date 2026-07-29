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
  common_name           = "argo.ai.coder.com"
  ssl_vol_friendly_name = replace(local.common_name, ".", "-")
}

# https://github.com/aws/containers-roadmap/issues/2736
# https://github.com/aws/containers-roadmap/issues/2736#issuecomment-4248984220
# TLDR: Custom URL in front of Argo not possible.
resource "kubernetes_manifest" "cloudfront-argo" {

  wait {
    fields = {
      "status.health.status" = "Healthy"
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
      name        = "${var.region}.cloudfront-argo"
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
          releaseName = "cloudfront-argocd"
          values = yamlencode({
            extra = {
              cloudfront = {
                domainName   = local.common_name
                lbDomainName = trimprefix(trimprefix(var.argocd_server_url, "https://"), "http://")
                comment      = "CloudFront Distribution for the EKS ArgoCD Capability."
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
        namespace = "cloudfront-argocd"
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