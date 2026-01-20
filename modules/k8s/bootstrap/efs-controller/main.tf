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
# https://github.com/kubernetes-sigs/aws-efs-csi-driver/blob/master/docs/install.md
##

variable "cluster_name" {
  type = string
}

variable "role_name" {
  type    = string
  default = ""
}

variable "cluster_oidc_provider_arn" {
  type = string
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
}

variable "service_account_annotations" {
  type    = map(string)
  default = {}
}

variable "replace" {
  type    = bool
  default = false
}

data "aws_region" "this" {}

locals {
  role_name = var.role_name == "" ? "efs-controller-${data.aws_region.this.region}" : var.role_name
}

module "oidc-role" {
  source       = "../../../security/role/access-entry"
  name         = local.role_name
  cluster_name = var.cluster_name
  policy_arns = {
    "AmazonEFSCSIDriverPolicy" = "arn:aws:iam::aws:policy/service-role/AmazonEFSCSIDriverPolicy"
  }
  cluster_policy_arns = {
    "AmazonEKSClusterAdminPolicy" = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  }
  oidc_principals = {
    "${var.cluster_oidc_provider_arn}" = ["system:serviceaccount:*:*"]
  }
  tags = var.tags
}

resource "helm_release" "efs-controller" {
  name             = "aws-efs-csi-driver"
  namespace        = var.namespace
  chart            = "aws-efs-csi-driver"
  repository       = "https://kubernetes-sigs.github.io/aws-efs-csi-driver/"
  create_namespace = true
  upgrade_install  = true
  skip_crds        = false
  replace          = var.replace
  wait             = true
  wait_for_jobs    = true
  version          = var.chart_version
  timeout          = 120 # in seconds

  values = [yamlencode({
    controller = {
      serviceAccount = {
        # https://github.com/kubernetes-sigs/aws-efs-csi-driver/blob/master/docs/install.md
        annotations = merge({
          "eks.amazonaws.com/role-arn" = module.oidc-role.role_arn
        }, var.service_account_annotations)
      }
    }
  })]
}

output "oidc_role_arn" {
  value = module.oidc-role.role_arn
}