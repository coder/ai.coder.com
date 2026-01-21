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
# https://kubernetes-sigs.github.io/aws-load-balancer-controller/latest/
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

variable "vpc_id" {
  description = "(Optional). Set this when your pods can't use the IMDS to auto-determine this"
  type = string
  default = ""
}

variable "node_selector" {
  type    = map(string)
  default = {}
}

variable "create_alb_class" {
  type = bool
  default = true
}

data "aws_region" "this" {}

data "aws_caller_identity" "this" {}

locals {
  region      = var.policy_resource_region == "" ? data.aws_region.this.region : var.policy_resource_region
  account_id  = var.policy_resource_account == "" ? data.aws_caller_identity.this.account_id : var.policy_resource_account
  policy_name = var.policy_name == "" ? "${var.cluster_name}-lb-ctrl-${data.aws_region.this.region}" : var.policy_name
  role_name   = var.role_name == "" ? "${var.cluster_name}-lb-ctrl-${data.aws_region.this.region}" : var.role_name
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
  oidc_principals = {
    "${var.cluster_oidc_provider_arn}" = ["system:serviceaccount:*:*"]
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
  upgrade_install  = true
  skip_crds        = false
  wait             = true
  wait_for_jobs    = true
  version          = var.chart_version
  timeout          = 300 # in seconds

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
    vpcId = var.vpc_id
    enableCertManager      = var.enable_cert_manager
    nodeSelector           = var.node_selector
    serviceTargetENISGTags = local.service_target_eni_sg_tags
    serviceMutatorWebhookConfig = {
      # Ref - https://github.com/awslabs/data-on-eks/issues/458
      failurePolicy = "Ignore"
    }
  })]
}

resource "kubernetes_manifest" "alb-class-params" {
  count = var.create_alb_class ? 1 : 0
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
  count = var.create_alb_class ? 1 : 0
  depends_on = [helm_release.lb-controller, kubernetes_manifest.alb-class-params[0]]
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