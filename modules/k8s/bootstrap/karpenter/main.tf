terraform {
  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.17.0"
    }
    kubernetes = {
      source = "hashicorp/kubernetes"
    }
    aws = {
      source = "hashicorp/aws"
    }
  }
}

variable "cluster_name" {
  type = string
}

variable "cluster_oidc_provider_arn" {
  type = string
}

variable "cluster_oidc_provider" {
  type = string
}

variable "namespace" {
  type    = string
  default = "karpenter"
}

variable "chart_version" {
  type = string
}

variable "karpenter_queue_name" {
  type    = string
  default = ""
}

variable "karpenter_queue_rule_name" {
  type    = string
  default = ""
}

variable "karpenter_controller_role_name" {
  type    = string
  default = ""
}

variable "karpenter_controller_role_policies" {
  type    = map(string)
  default = {}
}

variable "karpenter_controller_policy_name" {
  type    = string
  default = ""
}

variable "karpenter_controller_policy_statements" {
  type = list(object({
    effect    = optional(string, "Allow"),
    actions   = optional(list(string), []),
    resources = optional(list(string), [])
  }))
  default = []
}

variable "karpenter_node_role_name" {
  type    = string
  default = ""
}

variable "karpenter_node_role_policies" {
  type    = map(string)
  default = {}
}

variable "karpenter_tags" {
  type    = map(string)
  default = {}
}

variable "karpenter_role_tags" {
  type    = map(string)
  default = {}
}

variable "karpenter_node_role_tags" {
  type    = map(string)
  default = {}
}

variable "iam_role_use_name_prefix" {
  type = bool
  default = true
}

variable "node_iam_role_use_name_prefix" {
  type = bool
  default = true
}

variable "ec2nodeclass_configs" {
  type = list(object({
    name                 = string
    node_role_name       = optional(string, "")
    ami_alias            = optional(string, "al2023@latest")
    subnet_selector_tags = map(string)
    sg_selector_tags     = map(string)
    user_data            = optional(string, "")
    block_device_mappings = optional(list(object({
      device_name = string
      ebs = object({
        volume_size           = string
        volume_type           = string
        encrypted             = optional(bool, false)
        delete_on_termination = optional(bool, true)
      })
    })), [])
  }))
  default = []
}

variable "nodepool_configs" {
  type = list(object({
    name        = string
    node_labels = map(string)
    node_taints = optional(list(object({
      key    = string
      value  = string
      effect = string
    })), [])
    node_requirements = optional(list(object({
      key      = string
      operator = string
      values   = list(string)
    })), [])
    node_class_ref_name             = string
    node_expires_after              = optional(string, "Never")
    disruption_consolidation_policy = optional(string, "WhenEmpty")
    disruption_consolidate_after    = optional(string, "1m")
  }))
  default = []
}

variable "node_selector" {
  type    = map(string)
  default = {}
}

data "aws_region" "this" {}

locals {
  std_karpenter_format             = "${var.cluster_name}-kptr-${data.aws_region.this.region}"
  karpenter_queue_name             = var.karpenter_queue_name == "" ? "${var.cluster_name}-kptr" : var.karpenter_queue_name
  karpenter_queue_rule_name        = var.karpenter_queue_rule_name == "" ? "${var.cluster_name}-kptr" : var.karpenter_queue_rule_name
  karpenter_controller_role_name   = var.karpenter_controller_role_name == "" ? "${local.std_karpenter_format}-ctrl" : var.karpenter_controller_role_name
  karpenter_controller_policy_name = var.karpenter_controller_policy_name == "" ? local.std_karpenter_format : var.karpenter_controller_policy_name
  karpenter_node_role_name         = var.karpenter_node_role_name == "" ? "${local.std_karpenter_format}-node" : var.karpenter_node_role_name
}

data "aws_iam_policy_document" "sts" {
  statement {
    effect    = "Allow"
    actions   = ["sts:*"]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "sts" {
  name_prefix = "${var.cluster_name}-sts-"
  path        = "/"
  description = "Assume Role Policy"
  policy      = data.aws_iam_policy_document.sts.json
}

data "aws_iam_policy_document" "kptr_ctrl_assume_role_policy" {
  statement {
    effect = "Allow"

    principals {
      type        = "Federated"
      identifiers = [var.cluster_oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.cluster_oidc_provider}:sub"
      values   = ["system:serviceaccount:karpenter:karpenter"]
    }

    # https://aws.amazon.com/premiumsupport/knowledge-center/eks-troubleshoot-oidc-and-irsa/?nc1=h_ls
    condition {
      test     = "StringEquals"
      variable = "${var.cluster_oidc_provider}:aud"
      values   = ["sts.amazonaws.com"]
    }

    actions = ["sts:AssumeRoleWithWebIdentity"]
  }
}

module "karpenter" {
  source  = "terraform-aws-modules/eks/aws//modules/karpenter"
  version = "21.14.0"

  cluster_name     = var.cluster_name
  queue_name       = local.karpenter_queue_name
  rule_name_prefix = "${local.karpenter_queue_rule_name}-"

  # Karpenter Controller Role
  create_iam_role          = true
  iam_role_name            = local.karpenter_controller_role_name
  iam_role_use_name_prefix = var.iam_role_use_name_prefix
  iam_role_policies        = var.karpenter_controller_role_policies
  iam_role_source_assume_policy_documents = [
    data.aws_iam_policy_document.kptr_ctrl_assume_role_policy.json,
  ]

  # Karpenter Controller Policies
  iam_policy_use_name_prefix = true
  iam_policy_name            = local.karpenter_controller_policy_name
  iam_policy_statements = concat([{
    effect    = "Allow",
    actions   = toset(["iam:PassRole"]),
    resources = toset(["*"]),
  }], var.karpenter_controller_policy_statements)

  # Karpenter Node Role
  create_node_iam_role          = true
  node_iam_role_name            = local.karpenter_node_role_name
  node_iam_role_use_name_prefix = var.node_iam_role_use_name_prefix
  node_iam_role_additional_policies = merge({
    AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
    STSAssumeRole                = aws_iam_policy.sts.arn
  }, var.karpenter_node_role_policies)

  create_pod_identity_association = false
  enable_spot_termination = true

  ### DEPRECATED in v21.
  # enable_irsa             = true
  # irsa_oidc_provider_arn = var.cluster_oidc_provider_arn
  # enable_pod_identity     = false


  # tags = merge(var.tags, var.karpenter_tags)
  # iam_role_tags = merge(var.tags, var.karpenter_role_tags)
  # node_iam_role_tags = merge(var.tags, var.karpenter_node_role_tags)
}

resource "helm_release" "karpenter" {
  depends_on       = [module.karpenter]
  name             = "karpenter"
  namespace        = var.namespace
  chart            = "karpenter"
  repository       = "oci://public.ecr.aws/karpenter"
  create_namespace = true
  upgrade_install  = true
  skip_crds        = false
  wait             = true
  wait_for_jobs    = true
  version          = var.chart_version
  timeout          = 120 # in seconds

  values = [yamlencode({
    controller = {
      resources = {
        limits = {
          cpu    = "1000m"
          memory = "2Gi"
        }
        requests = {
          cpu    = "500m"
          memory = "1Gi"
        }
      }
    }
    dnsPolicy    = "ClusterFirst"
    nodeSelector = var.node_selector
    replicas     = 2
    serviceAccount = {
      annotations = {
        "eks.amazonaws.com/role-arn" = module.karpenter.iam_role_arn
      }
    }
    settings = {
      clusterName = var.cluster_name
      featureGates = {
        spotToSpotConsolidation = true
      }
      interruptionQueue = module.karpenter.queue_name
    }
  })]
}

module "ec2nodeclass" {
  count                 = length(var.ec2nodeclass_configs)
  source                = "../../objects/ec2nodeclass"
  name                  = var.ec2nodeclass_configs[count.index].name
  node_role_name        = var.ec2nodeclass_configs[count.index].node_role_name == "" ? module.karpenter.node_iam_role_name : var.ec2nodeclass_configs[count.index].node_role_name
  ami_alias             = var.ec2nodeclass_configs[count.index].ami_alias
  subnet_selector_tags  = var.ec2nodeclass_configs[count.index].subnet_selector_tags
  sg_selector_tags      = var.ec2nodeclass_configs[count.index].sg_selector_tags
  block_device_mappings = var.ec2nodeclass_configs[count.index].block_device_mappings
  user_data             = var.ec2nodeclass_configs[count.index].user_data
}

resource "kubernetes_manifest" "ec2nodeclass" {
  depends_on = [helm_release.karpenter]
  count      = length(var.ec2nodeclass_configs)
  manifest   = yamldecode(module.ec2nodeclass[count.index].manifest)
}

resource "kubernetes_service_account_v1" "ctrl-role" {

  depends_on = [helm_release.karpenter]

  metadata {
    name = "ctrl-role"
    namespace = var.namespace
    annotations = {
      "eks.amazonaws.com/role-arn" = module.karpenter.iam_role_arn
    }
  }
}

resource "kubernetes_service_account_v1" "node-role" {

  depends_on = [helm_release.karpenter]

  metadata {
    name = "node-role"
    namespace = var.namespace
    annotations = {
      "eks.amazonaws.com/role-arn" = module.karpenter.node_iam_role_arn
    }
  }
}