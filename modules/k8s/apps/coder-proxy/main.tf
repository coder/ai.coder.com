terraform {
  required_providers {
    local = {
      source  = "hashicorp/local"
      version = "~> 2.0"
    }
  }
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
  description = "Kubernetes namespace where Coder workspace proxy will be deployed"
  type        = string
  validation {
    condition     = length(var.namespace) > 0
    error_message = "Namespace must not be empty"
  }
}

variable "coder_helm_version" {
  description = "Version of the Coder Helm chart to deploy for workspace proxy"
  type        = string
  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.coder_helm_version))
    error_message = "Helm version must be in semver format (e.g., 2.23.0)"
  }
}

variable "image_repo" {
  description = "Container image repository for Coder workspace proxy"
  type        = string
  default     = "ghcr.io/coder/coder"
}

variable "image_tag" {
  description = "Container image tag for Coder workspace proxy"
  type        = string
  default     = "latest"
}

variable "image_pull_policy" {
  description = "Image pull policy for Coder workspace proxy container"
  type        = string
  default     = "IfNotPresent"
  validation {
    condition     = contains(["Always", "IfNotPresent", "Never"], var.image_pull_policy)
    error_message = "Image pull policy must be one of: Always, IfNotPresent, Never"
  }
}

variable "image_pull_secrets" {
  description = "List of image pull secret names for private container registries"
  type        = list(string)
  default     = []
}

variable "replica_count" {
  description = "Number of Coder workspace proxy replicas to run"
  type        = number
  default     = 0
  validation {
    condition     = var.replica_count >= 0
    error_message = "Replica count must be non-negative"
  }
}

variable "env_vars" {
  description = "Additional environment variables for Coder workspace proxy"
  type        = map(string)
  default     = {}
}

variable "load_balancer_class" {
  description = "Load balancer class for the workspace proxy service (e.g., service.k8s.aws/nlb)"
  type        = string
  default     = "service.k8s.aws/nlb"
}

variable "resource_request" {
  description = "Kubernetes resource requests for CPU and memory"
  type = object({
    cpu    = string
    memory = string
  })
  default = {
    cpu    = "250m"
    memory = "512Mi"
  }
  validation {
    condition     = can(regex("^[0-9]+(\\.[0-9]+)?(m|[KMGT]i?)?$", var.resource_request.cpu))
    error_message = "CPU must be in Kubernetes format (e.g., 250m, 0.25, 1)"
  }
  validation {
    condition     = can(regex("^[0-9]+(\\.[0-9]+)?([EPTGMK]i?)?$", var.resource_request.memory))
    error_message = "Memory must be in Kubernetes format (e.g., 512Mi, 1Gi)"
  }
}

variable "resource_limit" {
  description = "Kubernetes resource limits for CPU and memory"
  type = object({
    cpu    = string
    memory = string
  })
  default = {
    cpu    = "500m"
    memory = "1Gi"
  }
  validation {
    condition     = can(regex("^[0-9]+(\\.[0-9]+)?(m|[KMGT]i?)?$", var.resource_limit.cpu))
    error_message = "CPU must be in Kubernetes format (e.g., 500m, 0.5, 1)"
  }
  validation {
    condition     = can(regex("^[0-9]+(\\.[0-9]+)?([EPTGMK]i?)?$", var.resource_limit.memory))
    error_message = "Memory must be in Kubernetes format (e.g., 1Gi, 1024Mi)"
  }
}

variable "service_annotations" {
  description = "Annotations to apply to the workspace proxy service (e.g., for load balancer config)"
  type        = map(string)
  default     = {}
}

variable "service_account_annotations" {
  description = "Annotations to apply to the workspace proxy service account"
  type        = map(string)
  default     = {}
}

variable "node_selector" {
  description = "Node labels for pod assignment"
  type        = map(string)
  default     = {}
}

variable "tolerations" {
  description = "Pod tolerations for node taints"
  type = list(object({
    key      = string
    operator = optional(string, "Equal")
    value    = string
    effect   = optional(string, "NoSchedule")
  }))
  default = []
}

variable "topology_spread_constraints" {
  description = "Topology spread constraints to control pod distribution across failure domains"
  type = list(object({
    max_skew           = number
    topology_key       = string
    when_unsatisfiable = optional(string, "DoNotSchedule")
    label_selector = object({
      match_labels = map(string)
    })
    match_label_keys = list(string)
  }))
  default = []
}

variable "pod_anti_affinity_preferred_during_scheduling_ignored_during_execution" {
  description = "Preferred pod anti-affinity rules to spread pods across nodes"
  type = list(object({
    weight = number
    pod_affinity_term = object({
      label_selector = object({
        match_labels = map(string)
      })
      topology_key = string
    })
  }))
  default = []
}

variable "primary_access_url" {
  description = "Primary URL for accessing the main Coder deployment"
  type        = string
  validation {
    condition     = can(regex("^https?://", var.primary_access_url))
    error_message = "Primary access URL must start with http:// or https://"
  }
}

variable "proxy_access_url" {
  description = "URL for accessing the workspace proxy"
  type        = string
  validation {
    condition     = can(regex("^https?://", var.proxy_access_url))
    error_message = "Proxy access URL must start with http:// or https://"
  }
}

variable "proxy_wildcard_url" {
  description = "Wildcard URL for workspace proxy (e.g., https://*.proxy.example.com)"
  type        = string
  validation {
    condition     = can(regex("^https?://", var.proxy_wildcard_url))
    error_message = "Proxy wildcard URL must start with http:// or https://"
  }
}

variable "termination_grace_period_seconds" {
  description = "Grace period for pod termination in seconds"
  type        = number
  default     = 600
  validation {
    condition     = var.termination_grace_period_seconds >= 0
    error_message = "Termination grace period must be non-negative"
  }
}

variable "cert_config" {
  description = "TLS certificate configuration for the workspace proxy"
  type = object({
    name          = string
    create_secret = optional(bool, true)
    key_path      = string
    crt_path      = string
  })
}

variable "proxy_token_config" {
  description = "Proxy session token configuration for authenticating with the main Coder deployment"
  type = object({
    name = string
    path = string
  })
}

variable "patches" {
  description = "Kustomize patches to apply to generated Kubernetes resources"
  type = list(object({
    target = object({
      group   = optional(string, "")
      version = string
      kind    = string
      name    = string
    })
    expected = list(object({
      op    = string
      path  = string
      value = optional(any)
    }))
  }))
  default = []
}

locals {
  values_file    = "values.yaml"
  namespace_file = "namespace.yaml"
  patches = [for v in var.patches : {
    patch  = v.expected
    target = v.target
  }]
}

module "kustomization" {
  source    = "../../objects/kustomization"
  namespace = var.namespace
  helm_charts = [{
    name         = "coder"
    release_name = "coder-v2"
    repo         = "https://helm.coder.com/v2"
    namespace    = var.namespace
    include_crds = true
    version      = var.coder_helm_version
    values_file  = "./${local.values_file}"
  }]
  secret_generator = concat([{
    name      = var.proxy_token_config.name
    namespace = var.namespace
    behavior  = "create"
    files = [
      var.proxy_token_config.path
    ]
    options = {
      disable_name_suffix_hash = true
    }
    }], var.cert_config.create_secret ? [{
    name      = var.cert_config.name,
    namespace = var.namespace
    behavior  = "create"
    files = [
      var.cert_config.crt_path,
      var.cert_config.key_path,
    ]
    options = {
      disable_name_suffix_hash = true
    }
  }] : [])
  patches = local.patches
  resources = [
    local.namespace_file
  ]
}

module "namespace" {
  source = "../../objects/namespace"

  name = var.namespace
}

resource "local_file" "namespace" {
  filename = join("/", [var.path, local.namespace_file])
  content  = module.namespace.manifest
}

resource "local_file" "kustomization" {
  filename = "${var.path}/kustomization.yaml"
  content  = module.kustomization.manifest
}

locals {
  primary_env_vars = {
    CODER_PRIMARY_ACCESS_URL  = var.primary_access_url
    CODER_ACCESS_URL          = var.proxy_access_url
    CODER_WILDCARD_ACCESS_URL = var.proxy_wildcard_url
  }
  env_vars = concat([
    for k, v in merge(local.primary_env_vars, var.env_vars) : { name = k, value = v }
    ], [{
      name = "CODER_PROXY_SESSION_TOKEN"
      valueFrom = {
        secretKeyRef = {
          name = var.proxy_token_config.name
          key  = element(split("/", var.proxy_token_config.path), -1)
        }
      }
  }])
  pod_anti_affinity_preferred_during_scheduling_ignored_during_execution = [
    for k, v in var.pod_anti_affinity_preferred_during_scheduling_ignored_during_execution : {
      weight = v.weight
      podAffinityTerm = {
        labelSelector = {
          matchLabels = try(v.pod_affinity_term.label_selector.match_labels, {})
        }
        # Removed try() wrapper - topology_key is required string, not optional
        topologyKey = v.pod_affinity_term.topology_key
      }
    }
  ]
  topology_spread_constraints = [
    for k, v in var.topology_spread_constraints : {
      maxSkew           = v.max_skew
      topologyKey       = v.topology_key
      whenUnsatisfiable = v.when_unsatisfiable
      labelSelector = {
        matchLabels = try(v.label_selector.match_labels, {})
      }
      matchLabelKeys = v.match_label_keys

    }
  ]
}

resource "local_file" "values" {
  filename = join("/", [var.path, local.values_file])
  content = yamlencode({
    coder = {
      image = {
        repo        = var.image_repo
        tag         = var.image_tag
        pullPolicy  = var.image_pull_policy
        pullSecrets = var.image_pull_secrets
      }
      workspaceProxy = true
      env            = local.env_vars
      tls = {
        secretNames = [var.cert_config.name]
      }
      service = {
        enable                = true
        type                  = "LoadBalancer"
        sessionAffinity       = "None"
        externalTrafficPolicy = "Cluster"
        loadBalancerClass     = var.load_balancer_class
        annotations           = var.service_annotations
      }
      replicaCount = var.replica_count
      resources = {
        requests = var.resource_request
        limits   = var.resource_limit
      }
      serviceAccount = {
        annotations = var.service_account_annotations
      }
      nodeSelector              = var.node_selector
      tolerations               = var.tolerations
      topologySpreadConstraints = local.topology_spread_constraints
      affinity = {
        podAntiAffinity = {
          preferredDuringSchedulingIgnoredDuringExecution = local.pod_anti_affinity_preferred_during_scheduling_ignored_during_execution
        }
      }
      terminationGracePeriodSeconds = var.termination_grace_period_seconds
    }
  })

  lifecycle {
    # Recreate file on content changes to ensure consistency
    create_before_destroy = true
  }
}

output "namespace" {
  description = "The Kubernetes namespace where Coder workspace proxy is deployed"
  value       = var.namespace
}

output "helm_version" {
  description = "The version of the Coder Helm chart deployed for workspace proxy"
  value       = var.coder_helm_version
}

output "replica_count" {
  description = "The number of workspace proxy replicas configured"
  value       = var.replica_count
}

output "primary_access_url" {
  description = "The primary URL for accessing the main Coder deployment"
  value       = var.primary_access_url
}

output "proxy_access_url" {
  description = "The URL for accessing the workspace proxy"
  value       = var.proxy_access_url
}

output "proxy_wildcard_url" {
  description = "The wildcard URL for the workspace proxy"
  value       = var.proxy_wildcard_url
}

output "load_balancer_class" {
  description = "The load balancer class used by the workspace proxy service"
  value       = var.load_balancer_class
}

output "manifest_path" {
  description = "The directory path where Kubernetes manifests are generated"
  value       = var.path
}