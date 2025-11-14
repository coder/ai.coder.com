terraform {}

variable "name" {
  description = "Name of the Role resource"
  type        = string
  # Validation added because empty name would create invalid Kubernetes resource
  validation {
    condition     = length(var.name) > 0
    error_message = "name must not be empty"
  }
}

variable "namespace" {
  description = "Kubernetes namespace for the Role resource"
  type        = string
  # Validation added because empty namespace would create invalid Kubernetes resource
  validation {
    condition     = length(var.namespace) > 0
    error_message = "namespace must not be empty"
  }
}

variable "labels" {
  description = "Labels for the Role resource"
  type        = map(string)
  default     = {}
}

variable "annotations" {
  description = "Annotations for the Role resource"
  type        = map(string)
  default     = {}
}

variable "rules" {
  description = "List of RBAC rules defining permissions for the Role"
  type = list(object({
    api_groups     = optional(list(string), [""])
    resources      = optional(list(string), [""])
    resource_names = optional(list(string), [""])
    verbs          = optional(list(string), [""])
  }))
  default = []
  # Validation added because rules with empty resources or verbs create invalid RBAC permissions
  validation {
    condition = alltrue([
      for rule in var.rules : length(rule.resources) > 0 && length(rule.verbs) > 0
    ])
    error_message = "All rules must have at least one resource and one verb"
  }
}

output "manifest" {
  value = yamlencode({
    apiVersion = "rbac.authorization.k8s.io/v1"
    kind       = "Role"
    metadata = {
      name        = var.name
      namespace   = var.namespace
      labels      = var.labels
      annotations = var.annotations
    }
    rules = [for v in var.rules : {
      apiGroups     = v.api_groups
      resources     = v.resources
      resourceNames = v.resource_names
      verbs         = v.verbs
    }]
  })
}