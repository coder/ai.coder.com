terraform {}

variable "name" {
  description = "Name for the LiteLLM key rotation RBAC resources (role, service account, role binding)"
  type        = string
  validation {
    condition     = length(var.name) > 0
    error_message = "Name must not be empty"
  }
}

variable "namespace" {
  description = "Kubernetes namespace where the LiteLLM key rotation resources will be created"
  type        = string
  validation {
    condition     = length(var.namespace) > 0
    error_message = "Namespace must not be empty"
  }
}

variable "role_labels" {
  description = "Labels to apply to the LiteLLM key rotation role"
  type        = map(string)
  default     = {}
}

variable "role_annotations" {
  description = "Annotations to apply to the LiteLLM key rotation role"
  type        = map(string)
  default     = {}
}

variable "service_account_labels" {
  description = "Labels to apply to the LiteLLM key rotation service account"
  type        = map(string)
  default     = {}
}

variable "role_binding_labels" {
  description = "Labels to apply to the LiteLLM key rotation role binding"
  type        = map(string)
  default     = {}
}

variable "role_binding_annotations" {
  description = "Annotations to apply to the LiteLLM key rotation role binding"
  type        = map(string)
  default     = {}
}

variable "service_account_annotations" {
  description = "Annotations to apply to the LiteLLM key rotation service account"
  type        = map(string)
  default     = {}
}

variable "litellm_deployment_name" {
  description = "Name of the LiteLLM deployment that will be restarted during key rotation"
  type        = string
  validation {
    condition     = length(var.litellm_deployment_name) > 0
    error_message = "LiteLLM deployment name must not be empty"
  }
}

variable "litellm_secret_key_name" {
  description = "Name of the Kubernetes secret containing the LiteLLM master key"
  type        = string
  validation {
    condition     = length(var.litellm_secret_key_name) > 0
    error_message = "LiteLLM secret key name must not be empty"
  }
}

module "role" {
  source = "../../objects/role"

  name        = var.name
  namespace   = var.namespace
  labels      = var.role_labels
  annotations = var.role_annotations
  rules = [{
    api_groups     = [""]
    resources      = ["secrets"]
    resource_names = [var.litellm_secret_key_name]
    verbs          = ["get", "create", "update", "patch"]
    }, {
    api_groups     = ["apps", "extensions"]
    resources      = ["deployments"]
    resource_names = [var.litellm_deployment_name]
    verbs          = ["get", "patch"]
  }]
}

module "serviceaccount" {
  source = "../../objects/serviceaccount"

  name        = var.name
  namespace   = var.namespace
  labels      = var.service_account_labels
  annotations = var.service_account_annotations
}

module "rolebinding" {
  source = "../../objects/rolebinding"

  name        = var.name
  namespace   = var.namespace
  labels      = var.role_binding_labels
  annotations = var.role_binding_annotations
  # Use var.name directly as modules don't expose name outputs, only manifests
  role_ref = {
    name = var.name
  }
  subjects = [{
    # Added kind field for proper Kubernetes RBAC subject specification
    kind      = "ServiceAccount"
    name      = var.name
    namespace = var.namespace
  }]
}

# Output manifests for validation and debugging
output "role_manifest" {
  description = "The Kubernetes role manifest for LiteLLM key rotation"
  value       = module.role.manifest
}

output "serviceaccount_manifest" {
  description = "The Kubernetes service account manifest for LiteLLM key rotation"
  value       = module.serviceaccount.manifest
}

output "rolebinding_manifest" {
  description = "The Kubernetes role binding manifest for LiteLLM key rotation"
  value       = module.rolebinding.manifest
}

output "name" {
  description = "The name of the LiteLLM key rotation RBAC resources"
  value       = var.name
}

output "namespace" {
  description = "The Kubernetes namespace containing the LiteLLM key rotation resources"
  value       = var.namespace
}

output "service_account_name" {
  description = "The name of the service account for LiteLLM key rotation"
  value       = var.name
}