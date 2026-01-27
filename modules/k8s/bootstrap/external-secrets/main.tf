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

data "aws_region" "this" {}

data "aws_caller_identity" "this" {}

locals {
  region      = var.policy_resource_region == "" ? data.aws_region.this.region : var.policy_resource_region
  account_id  = var.policy_resource_account == "" ? data.aws_caller_identity.this.account_id : var.policy_resource_account
  policy_name = var.policy_name == "" ? "ext-sec" : var.policy_name
  role_name   = var.role_name == "" ? "ext-sec" : var.role_name
}

module "policy" {
  source      = "../../../security/policy"
  name        = local.policy_name
  path         = "/${var.cluster_name}/${data.aws_region.this.region}/"
  description = "External Secrets Policy."
  policy_json = data.aws_iam_policy_document.this.json
}

module "oidc-role" {
  source       = "../../../security/role/access-entry"
  name         = local.role_name
  path         = "/${var.cluster_name}/${data.aws_region.this.region}/"
  cluster_name = var.cluster_name
  policy_arns = {
    "ExternalSecrets"       = module.policy.policy_arn
  }
  cluster_policy_arns = {
    "AmazonEKSClusterAdminPolicy" = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy",
  }
  oidc_principals = {
    "${var.cluster_oidc_provider_arn}" = ["system:serviceaccount:*:*"]
  }
  tags = var.tags
}

locals {
  global_tolerations = [{
    key      = "CriticalAddonsOnly"
    operator = "Exists"
  }]
}

resource "helm_release" "chart" {
  name             = "external-secrets"
  namespace        = var.namespace
  chart            = "external-secrets"
  repository       = "https://charts.external-secrets.io"
  create_namespace = true
  upgrade_install  = true
  skip_crds        = false
  wait             = true
  wait_for_jobs    = true
  version          = var.chart_version
  timeout          = 120 # in seconds

  values = [yamlencode({
    nodeSelector = var.node_selector
    tolerations = local.global_tolerations
    webhook = {
      tolerations = local.global_tolerations
    }
    certController = {
      tolerations = local.global_tolerations
    }
    serviceAccount = {
      annotations = {
        "eks.amazonaws.com/role-arn" = module.oidc-role.role_arn
      }
    }
  })]
}