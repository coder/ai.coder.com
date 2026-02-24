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

##
# https://kubernetes-sigs.github.io/external-dns/latest/
# https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.13.2/docs/install/iam_policy.json
##

variable "cluster_name" {
  type = string
}

variable "cluster_oidc_provider_arn" {
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

variable "tags" {
  type    = map(string)
  default = {}
}

variable "namespace" {
  type = string
}

variable "chart_version" {
  type = string
  default = "1.20.0"
}

variable "node_selector" {
    type = map(string)
    default = {}
}

variable "tolerations" {
  type = list(map(any))
  default = []
}

data "aws_region" "this" {}

data "aws_caller_identity" "this" {}

variable "r53_config" {
  type = object({
    enabled = bool
    region = optional(string, "")
    account = optional(string, "")
    role_name = optional(string, "ext-dns")
    policy_name = optional(string, "ext-dns")
  })
  default = {
    enabled = false
    region = ""
    account = ""
    role_name = "ext-dns"
    policy_name = "ext-dns"
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
  description = "External DNS Policy."
  policy_json = data.aws_iam_policy_document.this.json
}

module "oidc-role" {

  count = var.r53_config.enabled ? 1 : 0

  source       = "../../../security/role/access-entry"
  name         = var.r53_config.role_name
  path         = "/${var.cluster_name}/${local.region}/"
  cluster_name = var.cluster_name
  policy_arns = {
    "ExternalDNS"       = module.policy[0].policy_arn
  }
  cluster_policy_arns = {
    "AmazonEKSClusterAdminPolicy" = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy",
  }
  oidc_principals = {
    "${var.cluster_oidc_provider_arn}" = ["system:serviceaccount:*:*"]
  }
  tags = var.tags
}

variable "cf_config" {
  type = object({
    enabled = bool
    token = string
    email = string
  })
  default = {
    enabled = false
    token = ""
    email = ""
  }
  sensitive = true
}

locals {
  # https://github.com/kubernetes-sigs/external-dns/blob/master/docs/tutorials/aws.md
  provider_aws = !var.r53_config.enabled ? null : {
    provider = { name = "aws" }
    env = [{
      name = "AWS_DEFAULT_REGION"
      value = data.aws_region.this.region
    }]
    serviceAccount = {
      annotations = {
          "eks.amazonaws.com/role-arn" = module.oidc-role[0].role_arn
      }
    }
    sources = [
      "ingress",
      "service"
    ]
    extraArgs = [ "--aws-zone-match-parent" ]
  }
  # https://github.com/kubernetes-sigs/external-dns/blob/master/docs/tutorials/cloudflare.md
  provider_cf = !var.cf_config.enabled ? null : {
    provider = { name = "cloudflare" }
    env = [{
      name = "CF_API_TOKEN"
      value = var.cf_config.token
    }]
  }
  values = merge(local.provider_cf, merge(local.provider_aws, {
    registry = "txt"
    txtPrefix = "%%{record_type}-txt-."
    txtOwnerId = "coder"
    policy = "sync" # Force cleanup + insertion of record.
    nodeSelector = var.node_selector
    tolerations = var.tolerations
  }))
}

resource "helm_release" "chart" {
  name             = "external-dns"
  namespace        = var.namespace
  chart            = "external-dns"
  repository       = "https://kubernetes-sigs.github.io/external-dns/"
  create_namespace = true
  upgrade_install  = true
  skip_crds        = false
  wait             = true
  wait_for_jobs    = true
  version          = var.chart_version
  timeout          = 120 # in seconds

  values = [yamlencode(local.values)]
}