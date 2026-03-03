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

##
# Manifest Setup Post Addon-Deployment
# Includes auxiliary resources depending on CRDs
## 

##
# EBS CSI StorageClasses
##

resource "kubernetes_manifest" "automode-gp3" {
  manifest = {
    apiVersion = "storage.k8s.io/v1"
    kind       = "StorageClass"
    metadata = {
      name = "gp3-automode"
    }
    provisioner       = "ebs.csi.eks.amazonaws.com"
    volumeBindingMode = "WaitForFirstConsumer"
    allowedTopologies = [{
      matchLabelExpressions = [{
        key    = "eks.amazonaws.com/compute-type"
        values = ["auto"]
      }]
    }]
    parameters = {
      type      = "gp3"
      encrypted = "true"
    }
  }
}

##
# Setup Cert-Manager ClusterIssuer
##

locals {
  cf_secret_key = "key"
}

resource "kubernetes_secret_v1" "cf" {
  metadata {
    name      = "cloudflare-token"
    namespace = var.cloudflare_secret_namespace
    annotations = {
      "custom.kubernetes.secret/key"   = local.cf_secret_key
      "custom.kubernetes.secret/email" = var.cloudflare_email
    }
  }
  data = {
    (local.cf_secret_key) = var.cloudflare_api_token
  }
}

resource "kubernetes_manifest" "issuer" {

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
    kind       = "ClusterIssuer"
    metadata = {
      labels = {}
      name   = var.cluster_issuer_name
    }
    spec = {
      acme = {
        privateKeySecretRef = {
          name = var.cluster_issuer_priv_key_ref
        }
        server = "https://acme-v02.api.letsencrypt.org/directory"
        solvers = [
          {
            dns01 = {
              cloudflare = {
                apiTokenSecretRef = {
                  key  = kubernetes_secret_v1.cf.metadata[0].annotations["custom.kubernetes.secret/key"]
                  name = kubernetes_secret_v1.cf.metadata[0].name
                }
                email = kubernetes_secret_v1.cf.metadata[0].annotations["custom.kubernetes.secret/email"]
              }
            }
          }
        ]
      }
    }
  }
}