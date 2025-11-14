terraform {
  required_providers {
    local = {
      source  = "hashicorp/local"
      version = "~> 2.0"
    }
  }
}

variable "path" {
  description = "Directory path where metrics-server manifests will be generated"
  type        = string
  validation {
    condition     = length(var.path) > 0
    error_message = "Path must not be empty"
  }
}

variable "namespace" {
  description = "Kubernetes namespace where metrics-server will be deployed"
  type        = string
  validation {
    condition     = length(var.namespace) > 0
    error_message = "Namespace must not be empty"
  }
}

variable "metrics_server_helm_version" {
  description = "Version of the metrics-server Helm chart to deploy"
  type        = string
  validation {
    condition     = length(var.metrics_server_helm_version) > 0
    error_message = "Metrics server Helm version must not be empty"
  }
}

variable "values_inline" {
  description = "Inline Helm values for metrics-server configuration (for custom settings)"
  type        = map(any)
  default     = {}
}

locals {
  kustomization_file = "kustomization.yaml"
}

module "kustomization" {
  source    = "../../objects/kustomization"
  namespace = var.namespace
  helm_charts = [{
    name          = "metrics-server"
    release_name  = "metrics-server"
    repo          = "https://kubernetes-sigs.github.io/metrics-server/"
    version       = var.metrics_server_helm_version
    namespace     = var.namespace
    include_crds  = true
    values_inline = var.values_inline
  }]
}

resource "local_file" "kustomization" {
  filename = join("/", [var.path, local.kustomization_file])
  content  = module.kustomization.manifest
}

output "namespace" {
  description = "The Kubernetes namespace where metrics-server is deployed"
  value       = var.namespace
}

output "helm_version" {
  description = "The version of the metrics-server Helm chart deployed"
  value       = var.metrics_server_helm_version
}

output "manifest_path" {
  description = "The directory path where Kubernetes manifests are generated"
  value       = var.path
}