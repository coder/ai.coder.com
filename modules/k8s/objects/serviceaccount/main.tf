terraform {
  required_providers {
    local = {
      source = "hashicorp/local"
    }
  }
}

variable "name" {
  type = string
  # Added validation because empty name causes Kubernetes resource errors
  validation {
    condition     = var.name != ""
    error_message = "name must not be empty."
  }
}

variable "namespace" {
  type = string
  # Added validation because empty namespace causes Kubernetes resource errors
  validation {
    condition     = var.namespace != ""
    error_message = "namespace must not be empty."
  }
}

variable "annotations" {
  type    = map(string)
  default = {}
}

variable "labels" {
  type    = map(string)
  default = {}
}

output "manifest" {
  value = yamlencode({
    apiVersion = "v1"
    kind       = "ServiceAccount"
    metadata = {
      name        = var.name
      namespace   = var.namespace
      annotations = var.annotations
      labels      = var.labels
    }
  })
}