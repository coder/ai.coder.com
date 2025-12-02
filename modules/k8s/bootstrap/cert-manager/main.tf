terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
      # Added version constraint for reproducibility and maintainability
      version = ">= 5.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "3.1.1"
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
}

variable "tags" {
  type    = map(string)
  default = {}
}

data "aws_region" "this" {}

data "aws_caller_identity" "this" {}

locals {
  # Cache data source lookups to avoid repeated API calls for performance
  region      = var.policy_resource_region == "" ? data.aws_region.this.region : var.policy_resource_region
  account_id  = var.policy_resource_account == "" ? data.aws_caller_identity.this.account_id : var.policy_resource_account
  policy_name = var.policy_name == "" ? "CertManager-${local.region}" : var.policy_name
  role_name   = var.role_name == "" ? "cert-manager-${local.region}" : var.role_name
}

module "policy" {
  source      = "../../../security/policy"
  name        = local.policy_name
  path        = "/"
  description = "CertManager for Route53 Policy"
  policy_json = data.aws_iam_policy_document.route53.json
}

module "oidc-role" {
  source       = "../../../security/role/access-entry"
  name         = local.role_name
  cluster_name = var.cluster_name
  policy_arns = {
    "CertManagerRoute53" = module.policy.policy_arn
  }
  cluster_policy_arns = {
    "AmazonEKSClusterAdminPolicy" = "arn:aws:iam::aws:policy/AmazonEKSClusterAdminPolicy"
  }
  # Restricted to specific service account instead of wildcard for least privilege
  oidc_principals = {
    "${var.cluster_oidc_provider_arn}" = ["system:serviceaccount:${var.namespace}:cert-manager-acme-dns01-route53"]
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

  # Added lifecycle management to handle upgrades properly
  lifecycle {
    create_before_destroy = true
  }
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
    kind = "ServiceAccount"
    # Reference actual cert-manager service account created by Helm chart
    name      = "cert-manager"
    namespace = kubernetes_namespace.this.metadata[0].name
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role.route53.metadata[0].name
  }
  # Ensure role binding waits for Helm release to create cert-manager service account
  depends_on = [helm_release.cert-manager]
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