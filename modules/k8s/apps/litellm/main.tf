terraform {
  required_providers {
    local = {
      source  = "hashicorp/local"
      version = "~> 2.0"
    }
  }
}

variable "name" {
  description = "Name of the LiteLLM deployment and associated resources"
  type        = string
  default     = "litellm"
}

variable "path" {
  description = "Directory path where Kubernetes manifests will be generated"
  type        = string
  validation {
    condition     = length(var.path) > 0
    error_message = "Path must not be empty"
  }
}

variable "namespace" {
  description = "Kubernetes namespace where LiteLLM will be deployed"
  type        = string
  # Added validation because empty namespace causes Kubernetes resource errors
  validation {
    condition     = var.namespace != ""
    error_message = "namespace must not be empty."
  }
}

variable "patches" {
  description = "Kustomize patches to apply to generated Kubernetes resources"
  type = list(object({
    expected = list(object({
      op    = string
      path  = string
      value = optional(any)
    }))
    target = object({
      group   = optional(string, "")
      version = string
      kind    = string
      name    = string
    })
  }))
  default = []
}

variable "service_account_name" {
  description = "Name of the Kubernetes service account for LiteLLM"
  type        = string
  validation {
    condition     = length(var.service_account_name) > 0
    error_message = "Service account name must not be empty"
  }
}

variable "service_account_labels" {
  description = "Labels to apply to the LiteLLM service account"
  type        = map(string)
  default     = {}
}

variable "service_account_annotations" {
  description = "Annotations to apply to the LiteLLM service account"
  type        = map(string)
  default     = {}
}

variable "deployment_labels" {
  description = "Labels to apply to the LiteLLM deployment"
  type        = map(string)
  default     = {}
}

variable "deployment_annotations" {
  description = "Annotations to apply to the LiteLLM deployment"
  type        = map(string)
  default     = {}
}

variable "deployment_template_labels" {
  description = "Labels to apply to the LiteLLM deployment pod template"
  type        = map(string)
  default     = {}
}

variable "deployment_template_annotations" {
  description = "Annotations to apply to the LiteLLM deployment pod template"
  type        = map(string)
  default     = {}
}

variable "deployment_replicas" {
  description = "Number of LiteLLM replicas to run"
  type        = number
  default     = 1
  validation {
    condition     = var.deployment_replicas >= 0
    error_message = "Deployment replicas must be non-negative"
  }
}

variable "deployment_selector" {
  description = "Label selector for the LiteLLM deployment"
  type        = map(string)
  default     = {}
}

variable "deployment_strategy" {
  description = "Deployment strategy for LiteLLM (RollingUpdate or Recreate)"
  type        = string
  default     = "RollingUpdate"
  validation {
    condition     = contains(["RollingUpdate", "Recreate"], var.deployment_strategy)
    error_message = "Deployment strategy must be either RollingUpdate or Recreate"
  }
}

variable "container_resources" {
  description = "Kubernetes resource requests and limits for CPU and memory"
  type = object({
    limits   = optional(map(string), {})
    requests = optional(map(string), {})
  })
  default = {}
}

variable "redis_config" {
  description = "Redis configuration for LiteLLM caching and rate limiting"
  type = object({
    port        = number
    ssl         = optional(bool, true)
    secret_path = string
  })
}

variable "postgres_config" {
  description = "PostgreSQL configuration for LiteLLM database storage"
  type = object({
    secret_path = string
  })
}

variable "litellm_config" {
  description = "LiteLLM application configuration including image, port, mode, and config paths"
  type = object({
    image                 = string
    port                  = optional(number, 4000)
    port_name             = optional(string, "")
    mode                  = optional(string, "PRODUCTION")
    log_level             = optional(string, "ERROR")
    secret_path           = string
    config_path           = string
    custom_function_paths = optional(list(string), [])
  })
}

variable "secret_mounts" {
  description = "Secrets to mount to LiteLLM"
  type = list(object({
    name       = string
    behavior   = optional(string, "create")
    files      = optional(list(string), [])
    read_only  = optional(bool, true)
    mount_path = optional(string, "/tmp")
    options = optional(object({
      disable_name_suffix_hash = optional(bool, true)
      }), {
      disable_name_suffix_hash = true
    })
  }))
  default = []
}

variable "env" {
  description = "Environment variables to set in the container"
  type        = map(string)
  default     = {}
}

variable "env_secret" {
  description = "Environment variables to set in the container from K8s Secrets."
  type        = map(string)
  default     = {}
}

variable "service_labels" {
  description = "Labels to apply to the LiteLLM service"
  type        = map(string)
  default     = {}
}

variable "service_annotations" {
  description = "Annotations to apply to the LiteLLM service"
  type        = map(string)
  default     = {}
}

variable "service_selector" {
  description = "Label selector for the LiteLLM service"
  type        = map(string)
  default     = {}
}

variable "service_ports" {
  description = "Custom service ports for LiteLLM (overrides default HTTP port)"
  type = list(object({
    name        = string
    port        = number
    target_port = number
    protocol    = string
  }))
  default = []
}

variable "ingress_class_name" {
  description = "Ingress class name for LiteLLM ingress (e.g., nginx, alb)"
  type        = string
  validation {
    condition     = length(var.ingress_class_name) > 0
    error_message = "Ingress class name must not be empty"
  }
}

variable "ingress_labels" {
  description = "Labels to apply to the LiteLLM ingress"
  type        = map(string)
  default     = {}
}

variable "ingress_annotations" {
  description = "Annotations to apply to the LiteLLM ingress"
  type        = map(string)
  default     = {}
}

variable "ingress_host" {
  description = "Hostname for LiteLLM ingress (e.g., litellm.example.com)"
  type        = string
  validation {
    condition     = length(var.ingress_host) > 0 && can(regex("^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?(\\.[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?)*$", var.ingress_host))
    error_message = "Ingress host must be a valid hostname (e.g., litellm.example.com)"
  }
}

variable "ingress_http_target_port" {
  description = "Target port for HTTP traffic on the LiteLLM service"
  type        = number
  default     = 80
}

locals {
  namespace_file       = "namespace.yaml"
  service_account_file = "serviceaccount.yaml"
  kustomization_file   = "kustomization.yaml"
  deployment_file      = "deployment.yaml"
  ingress_file         = "ingress.yaml"
  service_file         = "service.yaml"
}

module "namespace" {
  source = "../../objects/namespace"
  name   = var.namespace
}

locals {
  # Renamed loop variables for clarity because single-letter names reduce maintainability
  patches = [for patch in var.patches : {
    patch  = patch.expected
    target = patch.target
  }]
  config_maps = concat([{
    name       = replace(element(split("/", var.litellm_config.config_path), -1), "/[^a-zA-Z0-9-]/", "-")
    namespace  = var.namespace
    mount_path = "/app/${element(split("/", var.litellm_config.config_path), -1)}"
    sub_path   = element(split("/", var.litellm_config.config_path), -1)
    files      = [var.litellm_config.config_path]
    }], [for func_path in var.litellm_config.custom_function_paths : {
    name       = replace(element(split("/", func_path), -1), "/[^a-zA-Z0-9-]/", "-")
    namespace  = var.namespace
    mount_path = "/app/${element(split("/", func_path), -1)}"
    sub_path   = element(split("/", func_path), -1)
    files      = [func_path]
  }])
  secret_mounts = [for mount in var.secret_mounts : {
    name       = replace(mount.name, "/[^a-zA-Z0-9-]/", "-")
    namespace  = var.namespace
    behavior   = mount.behavior
    files      = mount.files
    read_only  = mount.read_only
    mount_path = mount.mount_path
    options    = mount.options
  }]
  secrets = concat([{
    name      = element(split("/", var.litellm_config.secret_path), -1)
    namespace = var.namespace
    envs      = [var.litellm_config.secret_path]
    }, {
    name      = element(split("/", var.redis_config.secret_path), -1)
    namespace = var.namespace
    envs      = [var.redis_config.secret_path]
    }, {
    name      = element(split("/", var.postgres_config.secret_path), -1)
    namespace = var.namespace
    envs      = [var.postgres_config.secret_path]
  }], local.secret_mounts)
}

module "kustomization" {
  source               = "../../objects/kustomization"
  namespace            = var.namespace
  config_map_generator = local.config_maps
  secret_generator     = local.secrets
  patches              = local.patches
  resources = [
    local.namespace_file,
    local.service_account_file,
    local.service_file,
    local.deployment_file,
    local.ingress_file
  ]
}

module "serviceaccount" {
  source      = "../../objects/serviceaccount"
  name        = var.service_account_name
  namespace   = var.namespace
  annotations = var.service_account_annotations
  labels      = var.service_account_labels
}

locals {
  # Cache port_name to avoid repeated conditional evaluation
  port_name = var.litellm_config.port_name == "" ? var.name : var.litellm_config.port_name
  env_secret = merge({
    LITELLM_MASTER_KEY = {
      name = element(split("/", var.litellm_config.secret_path), -1)
      key  = "master"
    }
    LITELLM_SALT_KEY = {
      name = element(split("/", var.litellm_config.secret_path), -1)
      key  = "salt"
    }
    REDIS_HOST = {
      name = element(split("/", var.redis_config.secret_path), -1)
      key  = "host"
    }
    REDIS_PASSWORD = {
      name = element(split("/", var.redis_config.secret_path), -1)
      key  = "password"
    }
    DATABASE_URL = {
      name = element(split("/", var.postgres_config.secret_path), -1)
      key  = "url"
    }
  }, var.env_secret)
  env = merge({
    LITELLM_MODE      = var.litellm_config.mode
    LITELLM_LOG_LEVEL = var.litellm_config.log_level
    LITELLM_LOG       = var.litellm_config.log_level
    REDIS_PORT        = var.redis_config.port
    REDIS_SSL         = var.redis_config.ssl ? "True" : "False"
  }, var.env)
}

module "deployment" {
  source               = "../../objects/deployment"
  name                 = var.name
  namespace            = var.namespace
  labels               = var.deployment_labels
  annotations          = var.deployment_annotations
  replicas             = var.deployment_replicas
  selector             = var.deployment_selector
  template_labels      = var.deployment_template_labels
  template_annotations = var.deployment_template_annotations
  strategy             = var.deployment_strategy
  service_account_name = var.service_account_name
  containers = [{
    name       = var.name
    image      = var.litellm_config.image
    env        = local.env
    env_secret = local.env_secret
    resources  = var.container_resources
    ports = [{
      name           = local.port_name
      protocol       = "TCP"
      container_port = var.litellm_config.port
    }]
    command = ["litellm", "--port", "${var.litellm_config.port}", "--config", "/app/config.yaml", "--detailed_debug"]
    volume_mounts = concat([for v in local.config_maps : {
      name       = v.name
      mount_path = v.mount_path
      sub_path   = v.sub_path
      read_only  = false
      }], [for v in local.secret_mounts : {
      name       = v.name
      mount_path = v.mount_path
      read_only  = v.read_only
    }])
  }]
  volumes_from_config_map = [for v in local.config_maps : v.name]
  volumes_from_secrets    = [for v in local.secret_mounts : v.name]
}

module "service" {
  source                  = "../../objects/service"
  name                    = var.name
  namespace               = var.namespace
  labels                  = var.service_labels
  annotations             = var.service_annotations
  internal_traffic_policy = "Cluster"
  ip_families             = ["IPv4"]
  ip_family_policy        = "SingleStack"
  ports = [{
    name        = "http"
    protocol    = "TCP"
    port        = var.ingress_http_target_port
    target_port = local.port_name
  }]
  selector = var.service_selector
  type     = "NodePort"
}

module "ingress" {
  source             = "../../objects/ingress"
  name               = var.name
  namespace          = var.namespace
  ingress_class_name = var.ingress_class_name
  labels             = var.ingress_labels
  annotations        = var.ingress_annotations
  rules = [{
    host = var.ingress_host
    http = {
      paths = [{
        path      = "/"
        path_type = "Prefix"
        backend = {
          service = {
            name = var.name
            port = {
              number = var.ingress_http_target_port
            }
          }
        }
      }]
    }
  }]
}

resource "local_file" "namespace" {
  filename = join("/", [var.path, local.namespace_file])
  content  = module.namespace.manifest
}

resource "local_file" "serviceaccount" {
  filename = join("/", [var.path, local.service_account_file])
  content  = module.serviceaccount.manifest
}

resource "local_file" "kustomization" {
  filename = join("/", [var.path, local.kustomization_file])
  content  = module.kustomization.manifest
}

resource "local_file" "deployment" {
  filename = join("/", [var.path, local.deployment_file])
  content  = module.deployment.manifest
}

resource "local_file" "service" {
  filename = join("/", [var.path, local.service_file])
  content  = module.service.manifest
}

resource "local_file" "ingress" {
  filename = join("/", [var.path, local.ingress_file])
  content  = module.ingress.manifest
}

output "namespace" {
  description = "The Kubernetes namespace where LiteLLM is deployed"
  value       = var.namespace
}

output "service_account_name" {
  description = "The name of the Kubernetes service account used by LiteLLM"
  value       = var.service_account_name
}

output "deployment_name" {
  description = "The name of the LiteLLM deployment"
  value       = var.name
}

output "ingress_host" {
  description = "The hostname configured for LiteLLM ingress"
  value       = var.ingress_host
}

output "ingress_class_name" {
  description = "The ingress class name used by LiteLLM"
  value       = var.ingress_class_name
}

output "replicas" {
  description = "The number of LiteLLM replicas configured"
  value       = var.deployment_replicas
}

output "manifest_path" {
  description = "The directory path where Kubernetes manifests are generated"
  value       = var.path
}