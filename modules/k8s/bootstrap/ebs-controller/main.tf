terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
      # Added version constraint for reproducibility and maintainability
      version = ">= 5.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "2.17.0"
    }
    kubernetes = {
      source = "hashicorp/kubernetes"
      # Added version constraint for reproducibility and maintainability
      version = ">= 2.20"
    }
  }
}

##
# https://github.com/kubernetes-sigs/aws-ebs-csi-driver/blob/master/docs/install.md
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
  role_name = var.role_name == "" ? "ebs-controller-${data.aws_region.this.region}" : var.role_name
}

module "oidc-role" {
  source       = "../../../security/role/access-entry"
  name         = local.role_name
  cluster_name = var.cluster_name
  policy_arns = {
    "AmazonEBSCSIDriverPolicy" = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
  }
  cluster_policy_arns = {
    "AmazonEKSClusterAdminPolicy" = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  }
  # Restricted to specific namespace and service account because wildcard allows any pod to assume EBS controller role
  oidc_principals = {
    "${var.cluster_oidc_provider_arn}" = ["system:serviceaccount:${var.namespace}:ebs-csi-controller-sa"]
  }
  tags = var.tags
}

resource "helm_release" "ebs-controller" {
  name             = "aws-ebs-csi-driver"
  namespace        = var.namespace
  chart            = "aws-ebs-csi-driver"
  repository       = "https://kubernetes-sigs.github.io/aws-ebs-csi-driver"
  create_namespace = true
  # Removed upgrade_install because it's not a valid helm_release attribute
  skip_crds     = false
  replace       = var.replace
  wait          = true
  wait_for_jobs = true
  version       = var.chart_version
  timeout       = 120 # in seconds

  values = [yamlencode({
    controller = {
      serviceAccount = {
        # https://github.com/kubernetes-sigs/aws-ebs-csi-driver/blob/master/docs/install.md
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