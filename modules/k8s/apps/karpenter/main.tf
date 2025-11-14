terraform {
  required_providers {
    local = {
      source  = "hashicorp/local"
      version = "~> 2.0"
    }
  }
}

variable "path" {
  description = "Directory path where Karpenter manifests will be generated"
  type        = string
  # Validation added because empty path would cause invalid file creation
  validation {
    condition     = length(var.path) > 0
    error_message = "path must not be empty"
  }
}

variable "namespace" {
  description = "Kubernetes namespace where Karpenter will be deployed"
  type        = string
  # Validation added because empty namespace would create invalid Kubernetes resources
  validation {
    condition     = length(var.namespace) > 0
    error_message = "namespace must not be empty"
  }
}

variable "cluster_name" {
  description = "EKS cluster name for Karpenter to manage"
  type        = string
  # Validation added because Karpenter requires valid cluster name for AWS API calls
  validation {
    condition     = length(var.cluster_name) > 0
    error_message = "cluster_name must not be empty"
  }
}

variable "karpenter_helm_version" {
  description = "Karpenter Helm chart version to deploy"
  type        = string
  # Validation added because empty version would cause Helm chart installation to fail
  validation {
    condition     = length(var.karpenter_helm_version) > 0
    error_message = "karpenter_helm_version must not be empty"
  }
}

variable "karpenter_queue_name" {
  description = "SQS queue name for Karpenter interruption handling"
  type        = string
  # Validation added because Karpenter requires valid SQS queue name for interruption handling
  validation {
    condition     = length(var.karpenter_queue_name) > 0
    error_message = "karpenter_queue_name must not be empty"
  }
}

variable "resources" {
  description = "Additional Kubernetes resource files to include in kustomization"
  type        = list(string)
  default     = []
}

variable "karpenter_resource_request" {
  description = "CPU and memory resource requests for Karpenter controller"
  type = object({
    cpu    = string
    memory = string
  })
  default = {
    cpu    = "250m"
    memory = "512Mi"
  }
  # Validation added because invalid resource values would cause Kubernetes pod creation to fail
  validation {
    condition     = can(regex("^[0-9]+(m|\\.[0-9]+)?$", var.karpenter_resource_request.cpu))
    error_message = "cpu must be a valid Kubernetes quantity (e.g., 250m, 1, 0.5)"
  }
  validation {
    condition     = can(regex("^[0-9]+(Mi|Gi|M|G|Ki|K)?$", var.karpenter_resource_request.memory))
    error_message = "memory must be a valid Kubernetes quantity (e.g., 512Mi, 1Gi)"
  }
}

variable "karpenter_resource_limit" {
  description = "CPU and memory resource limits for Karpenter controller"
  type = object({
    cpu    = string
    memory = string
  })
  default = {
    cpu    = "500m"
    memory = "1Gi"
  }
  # Validation added because invalid resource values would cause Kubernetes pod creation to fail
  validation {
    condition     = can(regex("^[0-9]+(m|\\.[0-9]+)?$", var.karpenter_resource_limit.cpu))
    error_message = "cpu must be a valid Kubernetes quantity (e.g., 500m, 1, 0.5)"
  }
  validation {
    condition     = can(regex("^[0-9]+(Mi|Gi|M|G|Ki|K)?$", var.karpenter_resource_limit.memory))
    error_message = "memory must be a valid Kubernetes quantity (e.g., 1Gi, 512Mi)"
  }
}

variable "karpenter_controller_annotations" {
  description = "Annotations for Karpenter service account (e.g., IAM role)"
  type        = map(string)
  default     = {}
}

variable "karpenter_replicas" {
  description = "Number of Karpenter controller replicas"
  type        = number
  default     = 0
}

variable "cluster_asg_node_labels" {
  description = "Node labels for Karpenter controller pod placement"
  type        = map(string)
  default     = {}
}

variable "ec2nodeclass_configs" {
  description = "List of EC2NodeClass configurations for Karpenter node provisioning"
  type = list(object({
    name                 = string
    node_role_name       = string
    ami_alias            = optional(string, "al2023@latest")
    subnet_selector_tags = map(string)
    sg_selector_tags     = map(string)
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
  # Validation added because empty name would cause invalid filename generation
  validation {
    condition     = alltrue([for config in var.ec2nodeclass_configs : length(config.name) > 0])
    error_message = "All ec2nodeclass_configs must have non-empty name"
  }
  # Validation added because empty node_role_name would cause Karpenter to fail IAM operations
  validation {
    condition     = alltrue([for config in var.ec2nodeclass_configs : length(config.node_role_name) > 0])
    error_message = "All ec2nodeclass_configs must have non-empty node_role_name"
  }
}

variable "nodepool_configs" {
  description = "List of NodePool configurations for Karpenter workload scheduling"
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
  # Validation added because empty name would cause invalid filename generation
  validation {
    condition     = alltrue([for config in var.nodepool_configs : length(config.name) > 0])
    error_message = "All nodepool_configs must have non-empty name"
  }
  # Validation added because empty node_class_ref_name would create invalid Kubernetes NodePool resource
  validation {
    condition     = alltrue([for config in var.nodepool_configs : length(config.node_class_ref_name) > 0])
    error_message = "All nodepool_configs must have non-empty node_class_ref_name"
  }
}

locals {
  values_file = "values.yaml"
  # Local created to detect filename collisions between ec2nodeclass and nodepool configs
  ec2nodeclass_names = toset([for config in var.ec2nodeclass_configs : config.name])
  nodepool_names     = toset([for config in var.nodepool_configs : config.name])
  name_overlap       = setintersection(local.ec2nodeclass_names, local.nodepool_names)
}

module "namespace" {
  source = "../../objects/namespace"
  name   = var.namespace
}

resource "local_file" "namespace" {
  filename = "${var.path}/namespace.yaml"
  content  = module.namespace.manifest
}

module "kustomization" {
  source    = "../../objects/kustomization"
  namespace = var.namespace
  helm_charts = [{
    name         = "karpenter"
    release_name = "karpenter"
    repo         = "oci://public.ecr.aws/karpenter"
    namespace    = var.namespace
    include_crds = true
    version      = var.karpenter_helm_version
    values_file  = "./${local.values_file}"
  }]
  resources = concat(["namespace.yaml"], [
    for v in var.ec2nodeclass_configs : "${v.name}.yaml"
    ], [
    for v in var.nodepool_configs : "${v.name}.yaml"
  ], var.resources)
}

resource "local_file" "kustomization" {
  filename = "${var.path}/kustomization.yaml"
  content  = module.kustomization.manifest
}

module "ec2nodeclass" {
  count                 = length(var.ec2nodeclass_configs)
  source                = "../../objects/ec2nodeclass"
  name                  = var.ec2nodeclass_configs[count.index].name
  node_role_name        = var.ec2nodeclass_configs[count.index].node_role_name
  ami_alias             = var.ec2nodeclass_configs[count.index].ami_alias
  subnet_selector_tags  = var.ec2nodeclass_configs[count.index].subnet_selector_tags
  sg_selector_tags      = var.ec2nodeclass_configs[count.index].sg_selector_tags
  block_device_mappings = var.ec2nodeclass_configs[count.index].block_device_mappings
}

resource "local_file" "ec2nodeclass" {
  count    = length(var.ec2nodeclass_configs)
  filename = "${var.path}/${var.ec2nodeclass_configs[count.index].name}.yaml"
  content  = module.ec2nodeclass[count.index].manifest
  # Lifecycle added because overlapping names would cause file overwrites
  lifecycle {
    precondition {
      condition     = length(local.name_overlap) == 0
      error_message = "ec2nodeclass_configs and nodepool_configs have overlapping names: ${join(", ", local.name_overlap)}. This would cause file collisions."
    }
  }
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

resource "local_file" "nodepool" {
  count    = length(var.nodepool_configs)
  filename = "${var.path}/${var.nodepool_configs[count.index].name}.yaml"
  content  = module.nodepool[count.index].manifest
}

resource "local_file" "values" {
  filename = join("/", [var.path, local.values_file])
  content = yamlencode({
    settings = {
      clusterName       = var.cluster_name
      interruptionQueue = var.karpenter_queue_name
      featureGates = {
        # Changed to boolean because Karpenter expects boolean value not string
        spotToSpotConsolidation = true
      }
    }
    serviceAccount = {
      annotations = var.karpenter_controller_annotations
    }
    controller = {
      resources = {
        requests = var.karpenter_resource_request
        limits   = var.karpenter_resource_limit
      }
    }
    nodeSelector = var.cluster_asg_node_labels
    replicas     = var.karpenter_replicas
    dnsPolicy    = "ClusterFirst"
  })
}

output "namespace" {
  description = "The Kubernetes namespace where Karpenter is deployed"
  value       = var.namespace
}

output "cluster_name" {
  description = "The EKS cluster name that Karpenter manages"
  value       = var.cluster_name
}

output "helm_version" {
  description = "The version of the Karpenter Helm chart deployed"
  value       = var.karpenter_helm_version
}

output "replica_count" {
  description = "The number of Karpenter controller replicas configured"
  value       = var.karpenter_replicas
}

output "ec2nodeclass_names" {
  description = "Names of the EC2NodeClass resources created"
  value       = [for config in var.ec2nodeclass_configs : config.name]
}

output "nodepool_names" {
  description = "Names of the NodePool resources created"
  value       = [for config in var.nodepool_configs : config.name]
}

output "queue_name" {
  description = "The SQS queue name used for Karpenter interruption handling"
  value       = var.karpenter_queue_name
}

output "manifest_path" {
  description = "The directory path where Kubernetes manifests are generated"
  value       = var.path
}