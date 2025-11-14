terraform {}

variable "name" {
  description = "Name of the RoleBinding resource"
  type        = string
  # Validation added because empty name would create invalid Kubernetes resource
  validation {
    condition     = length(var.name) > 0
    error_message = "name must not be empty"
  }
}

variable "namespace" {
  description = "Kubernetes namespace for the RoleBinding resource"
  type        = string
  # Validation added because empty namespace would create invalid Kubernetes resource
  validation {
    condition     = length(var.namespace) > 0
    error_message = "namespace must not be empty"
  }
}

variable "labels" {
  type    = map(string)
  default = {}
}

variable "annotations" {
  type    = map(string)
  default = {}
}

variable "role_ref" {
  description = "Reference to the Role or ClusterRole to bind"
  type = object({
    api_group = optional(string, "rbac.authorization.k8s.io")
    kind      = optional(string, "Role")
    name      = string
  })
  # Validation added because empty role_ref.name would create invalid RoleBinding
  validation {
    condition     = length(var.role_ref.name) > 0
    error_message = "role_ref.name must not be empty"
  }
}

variable "subjects" {
  description = "List of subjects (users, groups, service accounts) to bind to the role"
  type = list(object({
    kind      = optional(string, "ServiceAccount")
    name      = string
    namespace = optional(string, "")
  }))
  default = []
  # Validation added because subjects with empty names create invalid RoleBinding
  validation {
    condition = alltrue([
      for subject in var.subjects : length(subject.name) > 0
    ])
    error_message = "All subjects must have non-empty name"
  }
}

output "manifest" {
  value = yamlencode({
    apiVersion = "rbac.authorization.k8s.io/v1"
    kind       = "RoleBinding"
    metadata = {
      name        = var.name
      namespace   = var.namespace
      labels      = var.labels
      annotations = var.annotations
    }
    roleRef = {
      apiGroup = var.role_ref.api_group
      kind     = var.role_ref.kind
      name     = var.role_ref.name
    }
    subjects = [for v in var.subjects : {
      kind      = v.kind
      name      = v.name
      namespace = v.namespace == "" ? var.namespace : v.namespace
    }]
  })
}