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

variable "node_selector" {
  type    = map(string)
  default = {
    "kubernetes.io/os" = "linux"
  }
}

variable "tolerations" {
  type = list(map(any))
  default = []
}

##
# ACME Certificate Inputs
##

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

resource "kubernetes_namespace_v1" "this" {
  metadata {
    name = var.namespace
  }
}

resource "helm_release" "cert-manager" {
  name             = "cert-manager"
  namespace        = kubernetes_namespace_v1.this.metadata[0].name
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
    nodeSelector = var.node_selector
    tolerations = var.tolerations
    webhook = {
      tolerations = var.tolerations
    }
    cainjector = {
      tolerations = var.tolerations
    }
    startupapicheck = {
      tolerations = var.tolerations
    }
  })]
}

##
# Use Route53 for the DNS01 Challenge Provider
##

variable "r53_config" {
  type = object({
    enabled = bool
    region = optional(string, "")
    account = optional(string, "")
    role_name = optional(string, "crt-mgr")
    policy_name = optional(string, "crt-mgr")
  })
  default = {
    enabled = false
    region = ""
    account = ""
    role_name = "crt-mgr"
    policy_name = "crt-mgr"
  }
}

locals {
  region      = var.r53_config.region == "" ? data.aws_region.this.region : var.r53_config.region
  account_id  = var.r53_config.account == "" ? data.aws_caller_identity.this.account_id : var.r53_config.account
}

module "policy" {

  count = var.r53_config.enabled ? 1 : 0

  source      = "../../../security/policy"
  name        = var.r53_config.policy_name
  path         = "/${var.cluster_name}/${local.region}/"
  description = "Cert-Manager for R53 Policy"
  policy_json = data.aws_iam_policy_document.route53.json
}

module "oidc-role" {

  count = var.r53_config.enabled ? 1 : 0

  source       = "../../../security/role/access-entry"
  name         = var.r53_config.role_name
  path         = "/${var.cluster_name}/${local.region}/"
  cluster_name = var.cluster_name
  policy_arns = {
    "CertManagerR53" = module.policy[0].policy_arn
  }
  cluster_policy_arns = {
    "AmazonEKSClusterAdminPolicy" = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy",
  }
  oidc_principals = {
    "${var.cluster_oidc_provider_arn}" = ["system:serviceaccount:*:*"]
  }
  tags = var.tags
}

resource "kubernetes_service_account_v1" "r53" {

  count = var.r53_config.enabled ? 1 : 0

  metadata {
    name      = "${var.r53_config.role_name}"
    namespace = kubernetes_namespace_v1.this.metadata[0].name
    annotations = {
      "eks.amazonaws.com/role-arn" = module.oidc-role[0].role_arn
    }
  }
}

resource "kubernetes_role_v1" "r53" {

  count = var.r53_config.enabled ? 1 : 0

  metadata {
    name      = "${var.r53_config.role_name}-tokenrequest"
    namespace = kubernetes_namespace_v1.this.metadata[0].name
  }
  rule {
    api_groups     = [""]
    resources      = ["serviceaccounts/token"]
    resource_names = [kubernetes_service_account_v1.r53[0].metadata[0].name]
    verbs          = ["create"]
  }
}

resource "kubernetes_role_binding_v1" "r53" {

  count = var.r53_config.enabled ? 1 : 0

  metadata {
    name      = "${var.r53_config.role_name}-tokenrequest"
    namespace = kubernetes_namespace_v1.this.metadata[0].name
  }
  subject {
    kind      = "ServiceAccount"
    name      = "cert-manager"
    namespace = kubernetes_namespace_v1.this.metadata[0].name
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role_v1.r53[0].metadata[0].name
  }
}

##
# Use CloudFlare for the DNS01 Challenge Provider
##

variable "cf_config" {
  type = object({
    enabled = bool
    name = optional(string, "cloudflare")
    key = optional(string, "token.key")
    token = string
    email = string
  })
  default = {
    enabled = false
    name = "cloudflare"
    key = "token.key"
    token = ""
    email = ""
  }
  sensitive = true
}

locals {
  cf_annot_sec_key = "custom.kubernetes.secret/key"
  cf_annot_email_key = "custom.kubernetes.secret/email"
}

resource "kubernetes_secret_v1" "cloudflare" {

  count = var.cf_config.enabled ? 1 : 0

  metadata {
    name      = var.cf_config.name
    namespace = kubernetes_namespace_v1.this.metadata[0].name
    annotations = {
      "${local.cf_annot_sec_key}" = var.cf_config.key
      "${local.cf_annot_email_key}" = var.cf_config.email
    }
  }
  data = {
    "${var.cf_config.key}" = var.cf_config.token
  }
}