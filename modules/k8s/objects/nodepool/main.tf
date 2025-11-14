terraform {}

variable "name" {
  type = string
}

variable "node_labels" {
  type    = map(string)
  default = {}
}

variable "node_taints" {
  description = "List of Kubernetes taints to apply to nodes"
  type = list(object({
    key    = string
    value  = string
    effect = string
  }))
  default = []
  # Validation added because invalid taint effects cause Karpenter to fail node provisioning
  validation {
    condition = alltrue([
      for taint in var.node_taints : contains(["NoSchedule", "PreferNoSchedule", "NoExecute"], taint.effect)
    ])
    error_message = "All node_taints effect values must be one of: NoSchedule, PreferNoSchedule, NoExecute"
  }
}

variable "node_requirements" {
  description = "List of node requirements for Karpenter node selection"
  type = list(object({
    key      = string
    operator = string
    values   = list(string)
  }))
  default = []
  # Validation added because invalid operators cause Karpenter to fail node provisioning
  validation {
    condition = alltrue([
      for req in var.node_requirements : contains(["In", "NotIn", "Exists", "DoesNotExist", "Gt", "Lt"], req.operator)
    ])
    error_message = "All node_requirements operator values must be one of: In, NotIn, Exists, DoesNotExist, Gt, Lt"
  }
}

variable "node_class_ref_group" {
  type    = string
  default = "karpenter.k8s.aws"
}

variable "node_class_ref_kind" {
  type    = string
  default = "EC2NodeClass"
}

variable "node_class_ref_name" {
  description = "Name of the EC2NodeClass to reference"
  type        = string
  # Validation added because empty node class ref would create invalid NodePool
  validation {
    condition     = length(var.node_class_ref_name) > 0
    error_message = "node_class_ref_name must not be empty"
  }
}

variable "node_expires_after" {
  description = "Duration after which nodes expire (e.g., 720h, Never)"
  type        = string
  default     = "Never"
}

variable "disruption_consolidation_policy" {
  description = "Karpenter consolidation policy for node disruption"
  type        = string
  default     = "WhenEmpty"
  # Validation added because invalid policy causes Karpenter to fail
  validation {
    condition     = contains(["WhenEmpty", "WhenUnderutilized"], var.disruption_consolidation_policy)
    error_message = "disruption_consolidation_policy must be one of: WhenEmpty, WhenUnderutilized"
  }
}

variable "disruption_consolidate_after" {
  description = "Duration to wait before consolidating nodes (e.g., 1m, 5m)"
  type        = string
  default     = "1m"
}

output "manifest" {
  value = yamlencode({
    apiVersion = "karpenter.sh/v1"
    kind       = "NodePool"
    metadata = {
      name = var.name
    }
    spec = {
      template = {
        metadata = {
          labels = var.node_labels
        }
        spec = {
          taints       = var.node_taints
          requirements = var.node_requirements
          nodeClassRef = {
            group = var.node_class_ref_group
            kind  = var.node_class_ref_kind
            name  = var.node_class_ref_name
          }
          expireAfter = var.node_expires_after
        }
      }
      disruption = {
        consolidationPolicy = var.disruption_consolidation_policy
        consolidateAfter    = var.disruption_consolidate_after
      }
    }
  })
}