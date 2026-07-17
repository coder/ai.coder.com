provider "aws" {
  region  = var.region
  profile = var.profile
}

data "aws_caller_identity" "me" {}

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

data "aws_iam_openid_connect_provider" "this" {
  url = data.aws_eks_cluster.this.identity[0].oidc[0].issuer
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.controller.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.controller.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.controller.token
}

module "policy" {
  source      = "../../../../../../modules/security/policy"
  name        = "ext-sec"
  path        = "/${var.cluster_name}/${var.region}/"
  description = "External Secrets Policy."
  policy_json = data.aws_iam_policy_document.this.json
}

module "oidc-role" {
  source       = "../../../../../../modules/security/role/access-entry"
  name         = "ext-sec"
  path         = "/${var.cluster_name}/${var.region}/"
  cluster_name = var.cluster_name
  policy_arns = {
    "ExternalSecrets" = module.policy.policy_arn
  }
  cluster_policy_arns = {
    "AmazonEKSClusterAdminPolicy" = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy",
  }
  oidc_principals = {
    "${data.aws_iam_openid_connect_provider.this.arn}" = ["system:serviceaccount:*:*"]
  }
  tags = {}
}

locals {
  tolerations = [{
    key      = "CriticalAddonsOnly"
    operator = "Exists"
  }]
}

resource "kubernetes_manifest" "external-secrets" {

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
      name        = "${var.region}.external-secrets"
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
        repoURL        = "https://charts.external-secrets.io"
        chart          = "external-secrets"
        targetRevision = "2.7.0"
        helm = {
          releaseName = "external-secrets"
          values = yamlencode({
            nodeSelector = {}
            tolerations  = local.tolerations
            podAnnotations = {
              "checksum/config" = sha256(join(",", [
                jsonencode(module.oidc-role.role_arn)
              ]))
            }
            webhook = {
              tolerations = local.tolerations
            }
            certController = {
              tolerations = local.tolerations
            }
            serviceAccount = {
              annotations = {
                "eks.amazonaws.com/role-arn" = module.oidc-role.role_arn
              }
            }
          })
        }
      }
      destination = {
        server    = data.aws_eks_cluster.this.arn
        namespace = "external-secrets"
      }
      syncPolicy = {
        syncOptions = [
          "CreateNamespace=true",
          "Delete=confirm",
          "ServerSideApply=true"
        ]
      }
    }
  }
}

import {
  id = "apiVersion=argoproj.io/v1alpha1,kind=Application,namespace=argocd,name=${var.region}.external-secrets"
  to = kubernetes_manifest.external-secrets
}