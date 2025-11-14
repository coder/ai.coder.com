terraform {}

variable "name" {
  description = "Name of the Ingress resource"
  type        = string
  # Validation added because empty name would create invalid Kubernetes resource
  validation {
    condition     = length(var.name) > 0
    error_message = "name must not be empty"
  }
}

variable "namespace" {
  description = "Kubernetes namespace for the Ingress resource"
  type        = string
  # Validation added because empty namespace would create invalid Kubernetes resource
  validation {
    condition     = length(var.namespace) > 0
    error_message = "namespace must not be empty"
  }
}

variable "annotations" {
  description = "Annotations for the Ingress resource (e.g., ALB configuration)"
  type        = map(string)
  default     = {}
}

variable "labels" {
  description = "Labels for the Ingress resource"
  type        = map(string)
  default     = {}
}

variable "ingress_class_name" {
  description = "IngressClass name (e.g., alb, nginx)"
  type        = string
  # Validation added because empty ingress class would create invalid Kubernetes resource
  validation {
    condition     = length(var.ingress_class_name) > 0
    error_message = "ingress_class_name must not be empty"
  }
}

variable "rules" {
  description = "List of Ingress rules defining host-based routing and backend services"
  type = list(object({
    host = string
    http = object({
      paths = list(object({
        path      = string
        path_type = string
        backend = object({
          service = object({
            name = string
            port = object({
              number = number
            })
          })
        })
      }))
    })
  }))
  default = []
  # Validation added because empty host or service name would create invalid Ingress rules
  validation {
    condition = alltrue([
      for rule in var.rules : length(rule.host) > 0 && alltrue([
        for path in rule.http.paths : length(path.backend.service.name) > 0
      ])
    ])
    error_message = "All rules must have non-empty host and service names"
  }
}

locals {
  rules = [for v in var.rules : {
    host = v.host
    http = {
      paths = [for p in v.http.paths : {
        path     = p.path
        pathType = p.path_type
        backend  = p.backend
      }]
    }
  }]
}

output "manifest" {
  value = yamlencode({
    apiVersion = "networking.k8s.io/v1"
    kind       = "Ingress"
    metadata = {
      name        = var.name
      namespace   = var.namespace
      annotations = var.annotations
      labels      = var.labels
    }
    spec = {
      ingressClassName = var.ingress_class_name
      rules            = local.rules
    }
  })
}