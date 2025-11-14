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
# https://kubernetes-sigs.github.io/aws-load-balancer-controller/latest/
# https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.13.2/docs/install/iam_policy.json
##

variable "cluster_name" {
  description = "EKS cluster name for AWS Load Balancer Controller deployment"
  type        = string
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
  description = "Kubernetes namespace for AWS Load Balancer Controller resources"
  type        = string
}

variable "chart_version" {
  type = string
}

variable "enable_cert_manager" {
  type    = bool
  default = false
}

variable "service_target_eni_sg_tags" {
  type    = map(string)
  default = {}
}

variable "service_account_annotations" {
  type    = map(string)
  default = {}
}

variable "cluster_asg_node_labels" {
  type    = map(string)
  default = {}
}

data "aws_region" "this" {}

data "aws_caller_identity" "this" {}

locals {
  region      = var.policy_resource_region == "" ? data.aws_region.this.region : var.policy_resource_region
  account_id  = var.policy_resource_account == "" ? data.aws_caller_identity.this.account_id : var.policy_resource_account
  policy_name = var.policy_name == "" ? "LBController-${data.aws_region.this.region}" : var.policy_name
  role_name   = var.role_name == "" ? "lb-controller-${data.aws_region.this.region}" : var.role_name

  # Extract ELB ARN patterns for readability because repeated ARN construction reduces maintainability
  elb_arn_prefix = "arn:aws:elasticloadbalancing:${local.region}:${local.account_id}"
}

module "policy" {
  source      = "../../../security/policy"
  name        = local.policy_name
  path        = "/"
  description = "AWS Load Balancer Controller Policy"
  policy_json = data.aws_iam_policy_document.this.json
}

module "oidc-role" {
  source       = "../../../security/role/access-entry"
  name         = local.role_name
  cluster_name = var.cluster_name
  policy_arns = {
    "AmazonEKSLoadBalancingPolicy" = "arn:aws:iam::aws:policy/AmazonEKSLoadBalancingPolicy",
    "ElasticLoadBalancingReadOnly" = "arn:aws:iam::aws:policy/ElasticLoadBalancingReadOnly",
    "LoadBalancerController"       = module.policy.policy_arn
  }
  cluster_policy_arns = {
    "AmazonEKSClusterAdminPolicy" = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy",
  }
  # Restricted to specific namespace and service account because wildcard allows any pod to assume LB controller role
  oidc_principals = {
    "${var.cluster_oidc_provider_arn}" = ["system:serviceaccount:${var.namespace}:aws-load-balancer-controller"]
  }
  tags = var.tags
}

locals {
  service_target_eni_sg_tags = join(",", [
    for k, v in var.service_target_eni_sg_tags : "${k}=${v}"
  ])
}

resource "helm_release" "lb-controller" {
  name             = "aws-load-balancer-controller"
  namespace        = var.namespace
  chart            = "aws-load-balancer-controller"
  repository       = "https://aws.github.io/eks-charts"
  create_namespace = true
  # Removed invalid upgrade_install attribute - Terraform handles upgrades automatically
  skip_crds     = false
  wait          = true
  wait_for_jobs = true
  version       = var.chart_version
  timeout       = 120 # in seconds

  values = [yamlencode({
    clusterName = var.cluster_name
    serviceAccount = {
      create = true
      annotations = merge({
        "eks.amazonaws.com/role-arn" = module.oidc-role.role_arn
      }, var.service_account_annotations)
      automountServiceAccountToken = true
      imagePullSecrets             = []
    }
    enableCertManager      = var.enable_cert_manager
    nodeSelector           = var.cluster_asg_node_labels
    serviceTargetENISGTags = local.service_target_eni_sg_tags
  })]
}

resource "kubernetes_manifest" "alb-class-params" {
  depends_on = [helm_release.lb-controller]
  manifest = {
    apiVersion = "elbv2.k8s.aws/v1beta1"
    kind       = "IngressClassParams"
    metadata = {
      labels = {
        "app.kubernetes.io/name" : "aws-load-balancer-controller"
      }
      name = "alb"
    }
  }
}

resource "kubernetes_manifest" "alb-class" {
  depends_on = [helm_release.lb-controller, kubernetes_manifest.alb-class-params]
  manifest = {
    apiVersion = "networking.k8s.io/v1"
    kind       = "IngressClass"
    metadata = {
      labels = {
        "app.kubernetes.io/name" : "aws-load-balancer-controller"
      }
      name = "alb"
    }
    spec = {
      controller = "ingress.k8s.aws/alb"
      parameters = {
        apiGroup = "elbv2.k8s.aws"
        kind     = "IngressClassParams"
        name     = "alb"
      }
    }
  }
}

output "oidc_role_arn" {
  value = module.oidc-role.role_arn
}