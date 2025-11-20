terraform {
  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "2.17.0"
    }
    kubernetes = {
      source = "hashicorp/kubernetes"
      # Added version constraint for reproducibility and maintainability
      version = ">= 2.20"
    }
    aws = {
      source = "hashicorp/aws"
      # Added version constraint for reproducibility and maintainability
      version = ">= 5.0"
    }
  }
}

variable "cluster_name" {
  type = string
}

variable "cluster_oidc_provider_arn" {
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

variable "ec2nodeclass_configs" {
  type = list(object({
    name                 = string
    node_role_name       = optional(string, "")
    ami_alias            = optional(string, "al2023@latest")
    subnet_selector_tags = map(string)
    sg_selector_tags     = map(string)
    block_device_mappings = optional(list(object({
      device_name = string
      ebs = object({
        volume_size           = string # Kubernetes-style size with unit (e.g. "1400Gi", "50Gi")
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
  karpenter_controller_role_name   = var.karpenter_controller_role_name == "" ? local.std_karpenter_format : var.karpenter_controller_role_name
  karpenter_controller_policy_name = var.karpenter_controller_policy_name == "" ? local.std_karpenter_format : var.karpenter_controller_policy_name
  karpenter_node_role_name         = var.karpenter_node_role_name == "" ? local.std_karpenter_format : var.karpenter_node_role_name
}

data "aws_caller_identity" "this" {}

data "aws_iam_policy_document" "sts" {
  statement {
    effect = "Allow"
    # Restricted to AssumeRole only because sts:* grants excessive permissions
    actions = ["sts:AssumeRole"]
    # Scoped to account roles only because wildcard allows assuming any role
    resources = ["arn:aws:iam::${data.aws_caller_identity.this.account_id}:role/*"]
  }
}

resource "aws_iam_policy" "sts" {
  name_prefix = "sts"
  path        = "/"
  description = "Assume Role Policy"
  policy      = data.aws_iam_policy_document.sts.json
}

module "karpenter" {
  source  = "terraform-aws-modules/eks/aws//modules/karpenter"
  version = "20.34.0" # "21.3.1"

  cluster_name     = var.cluster_name
  queue_name       = local.karpenter_queue_name
  rule_name_prefix = "${local.karpenter_queue_rule_name}-"

  # Karpenter Controller Role
  create_iam_role          = true
  iam_role_name            = local.karpenter_controller_role_name
  iam_role_use_name_prefix = true
  iam_role_policies        = var.karpenter_controller_role_policies

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
  node_iam_role_use_name_prefix = true
  node_iam_role_additional_policies = merge({
    AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
    STSAssumeRole                = aws_iam_policy.sts.arn
  }, var.karpenter_node_role_policies)

  enable_irsa             = true
  enable_pod_identity     = false
  enable_spot_termination = true

  irsa_oidc_provider_arn = var.cluster_oidc_provider_arn

  tags               = var.karpenter_tags
  iam_role_tags      = var.karpenter_role_tags
  node_iam_role_tags = var.karpenter_node_role_tags
}

resource "helm_release" "karpenter" {
  depends_on       = [module.karpenter]
  name             = "karpenter"
  namespace        = var.namespace
  chart            = "karpenter"
  repository       = "oci://public.ecr.aws/karpenter"
  create_namespace = true
  # Removed invalid upgrade_install attribute
  skip_crds     = false
  wait          = true
  wait_for_jobs = true
  version       = var.chart_version
  timeout       = 120 # in seconds

  # Added lifecycle management for proper upgrade handling
  lifecycle {
    create_before_destroy = true
  }

  values = [yamlencode({
    controller = {
      resources = {
        limits = {
          cpu    = "500m"
          memory = "512Mi"
        }
        requests = {
          cpu    = "100m"
          memory = "256Mi"
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
        # Cost optimization - consolidate workloads to better-priced spot instances
        spotToSpotConsolidation = true
        # Future features - currently disabled
        staticCapacity   = false # New capacity management feature
        reservedCapacity = false # For Reserved Instance support
        nodeRepair       = false # Experimental - automatic node repair
        nodeOverlay      = false # Experimental - network overlay support
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
}

resource "kubernetes_manifest" "ec2nodeclass" {
  depends_on = [helm_release.karpenter]
  count      = length(var.ec2nodeclass_configs)
  manifest   = yamldecode(module.ec2nodeclass[count.index].manifest)
}

module "nodepool" {
  count                           = length(var.nodepool_configs)
  source                          = "../../objects/nodepool"
  name                            = var.nodepool_configs[count.index].name
  node_labels                     = var.nodepool_configs[count.index].node_labels
  node_taints                     = var.nodepool_configs[count.index].node_taints
  node_requirements               = var.nodepool_configs[count.index].node_requirements
  node_class_ref_name             = var.nodepool_configs[count.index].node_class_ref_name
  node_expires_after              = var.nodepool_configs[count.index].node_expires_after
  disruption_consolidation_policy = var.nodepool_configs[count.index].disruption_consolidation_policy
  disruption_consolidate_after    = var.nodepool_configs[count.index].disruption_consolidate_after
}

resource "kubernetes_manifest" "nodepool" {
  depends_on = [helm_release.karpenter]
  count      = length(var.nodepool_configs)
  manifest   = yamldecode(module.nodepool[count.index].manifest)
}

