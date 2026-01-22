terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.17.0"
    }
    kubernetes = {
      source = "hashicorp/kubernetes"
    }
  }
}

variable "cluster_name" {
  type = string
}

variable "role_name" {
  type    = string
  default = ""
}

variable "policy_name" {
  type    = string
  default = ""
}

variable "policy_resource_region" {
  type    = string
  default = ""
}

variable "policy_resource_account" {
  type    = string
  default = ""
}

variable "cluster_oidc_provider_arn" {
  type = string
}

##
# Kubernetes Inputs
##

variable "namespace" {
  type    = string
  default = "cert-manager"
}

variable "helm_timeout" {
  type    = number
  default = 120 # In Seconds
}

variable "helm_version" {
  type    = string
  default = "v1.18.2"
}

##
# Create Default Resources?
##

variable "create_default_cluster_issuer" {
  type = bool
  default = true
}

##
# ACME Certificate Inputs
##

variable "issuer_private_key_secret_name" {
  type    = string
  default = "issuer-account-key"
}

variable "acme_server_url" {
  type    = string
  default = "https://acme-v02.api.letsencrypt.org/directory"
}

variable "tags" {
  type    = map(string)
  default = {}
}

data "aws_region" "this" {}

data "aws_caller_identity" "this" {}

locals {
  region      = var.policy_resource_region == "" ? data.aws_region.this.region : var.policy_resource_region
  account_id  = var.policy_resource_account == "" ? data.aws_caller_identity.this.account_id : var.policy_resource_account
  policy_name = var.policy_name == "" ? "crt-mgr" : var.policy_name
  role_name   = var.role_name == "" ? "crt-mgr" : var.role_name
}

module "policy" {
  source      = "../../../security/policy"
  name        = local.policy_name
  path         = "/${var.cluster_name}/${data.aws_region.this.region}/"
  description = "CertManager for Route53 Policy"
  policy_json = data.aws_iam_policy_document.route53.json
}

module "oidc-role" {
  source       = "../../../security/role/access-entry"
  name         = local.role_name
  path         = "/${var.cluster_name}/${data.aws_region.this.region}/"
  cluster_name = var.cluster_name
  policy_arns = {
    "CertManagerRoute53" = module.policy.policy_arn
  }
  cluster_policy_arns = {
    "AmazonEKSClusterAdminPolicy" = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy",
  }
  oidc_principals = {
    "${var.cluster_oidc_provider_arn}" = ["system:serviceaccount:*:*"]
  }
  tags = var.tags
}

resource "kubernetes_namespace" "this" {
  metadata {
    name = var.namespace
  }
}

resource "helm_release" "cert-manager" {
  name             = "cert-manager"
  namespace        = kubernetes_namespace.this.metadata[0].name
  chart            = "cert-manager"
  repository       = "oci://quay.io/jetstack/charts"
  create_namespace = false
  upgrade_install  = true
  skip_crds        = false
  wait             = true
  wait_for_jobs    = true
  version          = var.helm_version
  timeout          = var.helm_timeout

  values = [yamlencode({
    crds = {
      enabled = true
    }
  })]
}

##
# Use Route53 for the DNS01 Challenge Provider
##

variable "use_route53" {
  type = bool
  default = false
}

variable "route53_region" {
  type = string
  default = "us-east-2"
}

variable "route53_sa_role" {
  type = string
  default = ""
}

resource "kubernetes_service_account" "route53" {
  metadata {
    name      = "cert-manager-acme-dns01-route53"
    namespace = kubernetes_namespace.this.metadata[0].name
    annotations = {
      "eks.amazonaws.com/role-arn" = module.oidc-role.role_arn
    }
  }
}

resource "kubernetes_role" "route53" {
  metadata {
    name      = "cert-manager-acme-dns01-route53-tokenrequest"
    namespace = kubernetes_namespace.this.metadata[0].name
  }
  rule {
    api_groups     = [""]
    resources      = ["serviceaccounts/token"]
    resource_names = [kubernetes_service_account.route53.metadata[0].name]
    verbs          = ["create"]
  }
}

resource "kubernetes_role_binding" "route53" {
  metadata {
    name      = "cert-manager-acme-dns01-route53-tokenrequest"
    namespace = kubernetes_namespace.this.metadata[0].name
  }
  subject {
    kind      = "ServiceAccount"
    name      = "cert-manager"
    namespace = kubernetes_namespace.this.metadata[0].name
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role.route53.metadata[0].name
  }
}

##
# Use CloudFlare for the DNS01 Challenge Provider
##

variable "use_cloudflare" {
  type = bool
  default = true
}

variable "cloudflare_token_secret_name" {
  type    = string
  default = "cloudflare-token"
}

variable "cloudflare_token_secret_key" {
  type    = string
  default = "token.key"
}

variable "cloudflare_token_secret" {
  type      = string
  sensitive = true
  default = ""
}

variable "cloudflare_token_secret_email" {
  type      = string
  sensitive = true
  default = ""
}

resource "kubernetes_secret" "cloudflare" {
  metadata {
    name      = var.cloudflare_token_secret_name
    namespace = kubernetes_namespace.this.metadata[0].name
  }
  data = {
    "${var.cloudflare_token_secret_key}" = var.cloudflare_token_secret
  }
}

# ----------------

locals {
  dns01_cf = {
    cloudflare = {
      apiTokenSecretRef = {
        key  = var.cloudflare_token_secret_key
        name = kubernetes_secret.cloudflare.metadata[0].name
      }
      email = var.cloudflare_token_secret_email
    }
  }
  dns01_r53 = {
    route53 = {
      region = var.route53_region
      auth = {
        kubernetes = {
          serviceAccountRef = {
            name = kubernetes_service_account.route53.metadata[0].name
          }
        }
      }
    }
  }
}

##
# Setup the default Cluster Issuer
##

resource "kubernetes_manifest" "default-issuer" {

  depends_on = [
    helm_release.cert-manager,
    kubernetes_secret.cloudflare
  ]

  count = var.create_default_cluster_issuer ? 1 : 0

  field_manager {
    force_conflicts = true
  }
  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind       = "ClusterIssuer"
    metadata = {
      labels = {}
      name   = "issuer"
    }
    spec = {
      acme = {
        privateKeySecretRef = {
          name = var.issuer_private_key_secret_name
        }
        server = var.acme_server_url
        solvers = [
          {
            dns01 = {
              cloudflare = {
                apiTokenSecretRef = {
                  key  = var.cloudflare_token_secret_key
                  name = kubernetes_secret.cloudflare.metadata[0].name
                }
                email = var.cloudflare_token_secret_email
              }
            }
          }
        ]
      }
    }
  }
}