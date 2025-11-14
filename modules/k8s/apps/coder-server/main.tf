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
  description = "Kubernetes namespace where Coder will be deployed"
  type        = string
  validation {
    condition     = length(var.namespace) > 0
    error_message = "Namespace must not be empty"
  }
}

variable "image_repo" {
  description = "Container image repository for Coder (e.g., ghcr.io/coder/coder)"
  type        = string
  validation {
    condition     = length(var.image_repo) > 0
    error_message = "Image repository must not be empty"
  }
}

variable "image_tag" {
  description = "Container image tag for Coder"
  type        = string
  validation {
    condition     = length(var.image_tag) > 0
    error_message = "Image tag must not be empty"
  }
}

variable "image_pull_policy" {
  description = "Image pull policy for Coder container (Always, IfNotPresent, or Never)"
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

variable "coder_helm_chart_ver" {
  description = "Version of the Coder Helm chart to deploy (must be in semver format)"
  type        = string
  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.coder_helm_chart_ver))
    error_message = "Helm chart version must be in semver format (e.g., 2.23.0)"
  }
}

variable "primary_access_url" {
  description = "Primary URL for accessing Coder (e.g., https://coder.example.com)"
  type        = string
  validation {
    condition     = can(regex("^https?://", var.primary_access_url))
    error_message = "Primary access URL must start with http:// or https://"
  }
}

variable "service_account_name" {
  description = "Name of the Kubernetes service account for Coder"
  type        = string
  validation {
    condition     = length(var.service_account_name) > 0
    error_message = "Service account name must not be empty"
  }
}

variable "service_account_labels" {
  description = "Labels to apply to the Coder service account"
  type        = map(string)
  default     = {}
}

variable "service_account_annotations" {
  description = "Annotations to apply to the Coder service account"
  type        = map(string)
  default     = {}
}

variable "extern_prov_service_account_name" {
  description = "Name of the service account for external provisioner workspaces"
  type        = string
  default     = "coder"
}

variable "extern_prov_service_account_annotations" {
  description = "Annotations for the external provisioner service account (e.g., for IRSA)"
  type        = map(string)
  default     = {}
}

variable "replica_count" {
  description = "Number of Coder server replicas to run for high availability"
  type        = number
  # Changed from 0 to 1 to ensure at least one Coder server pod runs by default
  default = 1
  validation {
    condition     = var.replica_count >= 1
    error_message = "Replica count must be at least 1 to ensure service availability"
  }
}

variable "env_vars" {
  description = "Additional environment variables for Coder server"
  type        = map(string)
  default     = {}
}

variable "resource_requests" {
  description = "Kubernetes resource requests for CPU and memory"
  type = object({
    cpu    = string
    memory = string
  })
  default = {
    cpu    = "2000m"
    memory = "4Gi"
  }
  validation {
    condition     = can(regex("^[0-9]+(\\.[0-9]+)?(m|[KMGT]i?)?$", var.resource_requests.cpu))
    error_message = "CPU must be in Kubernetes format (e.g., 2000m, 2, 0.5)"
  }
  validation {
    condition     = can(regex("^[0-9]+(\\.[0-9]+)?([EPTGMK]i?)?$", var.resource_requests.memory))
    error_message = "Memory must be in Kubernetes format (e.g., 4Gi, 2048Mi, 1G)"
  }
}

# https://coder.com/docs/admin/infrastructure/validated-architectures/1k-users#coderd-nodes
# 4 CPU's for other pods on the node (e.g. ebs-csi, kube-proxy)
variable "resource_limits" {
  description = "Kubernetes resource limits for CPU and memory"
  type = object({
    cpu    = string
    memory = string
  })
  default = {
    cpu    = "4000m"
    memory = "8Gi"
  }
  validation {
    condition     = can(regex("^[0-9]+(\\.[0-9]+)?(m|[KMGT]i?)?$", var.resource_limits.cpu))
    error_message = "CPU must be in Kubernetes format (e.g., 4000m, 4, 2.5)"
  }
  validation {
    condition     = can(regex("^[0-9]+(\\.[0-9]+)?([EPTGMK]i?)?$", var.resource_limits.memory))
    error_message = "Memory must be in Kubernetes format (e.g., 8Gi, 4096Mi, 2G)"
  }
}

variable "node_selector" {
  description = "Node labels for pod assignment (e.g., {\"node-type\" = \"coder\"})"
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

module "kustomization" {
  source    = "../../objects/kustomization"
  namespace = var.namespace
  helm_charts = [{
    name         = "coder"
    release_name = "coder-v2"
    repo         = "https://helm.coder.com/v2"
    namespace    = var.namespace
    include_crds = true
    version      = var.coder_helm_chart_ver
    values_file  = "./values.yaml"
    # Set empty secret_generator (no secrets to generate for this deployment)
    secret_generator = []
  }]
  resources = [
    "namespace.yaml"
  ]
}

resource "local_file" "kustomization" {
  filename = "${var.path}/kustomization.yaml"
  content  = module.kustomization.manifest
}

module "namespace" {
  source = "../../objects/namespace"

  name = var.namespace
}

resource "local_file" "namespace" {
  filename = "${var.path}/namespace.yaml"
  content  = module.namespace.manifest
}

module "serviceaccount" {
  source = "../../objects/serviceaccount"

  name        = var.service_account_name
  namespace   = var.namespace
  annotations = var.service_account_annotations
  labels      = var.service_account_labels
}

resource "local_file" "serviceaccount" {
  filename = "${var.path}/serviceaccount.yaml"
  content  = module.serviceaccount.manifest
}

locals {
  primary_env_vars = {
    CODER_URL = var.primary_access_url
  }
  env_vars = [
    for k, v in merge(local.primary_env_vars, var.env_vars) : { name = k, value = v }
  ]
  topology_spread_constraints = [
    for v in var.topology_spread_constraints : {
      maxSkew           = v.max_skew
      topologyKey       = v.topology_key
      whenUnsatisfiable = v.when_unsatisfiable
      labelSelector     = v.label_selector
      matchLabelKeys    = v.match_label_keys
    }
  ]
  # Shortened name for readability because full Kubernetes field name is excessively long
  pod_anti_affinity_preferred = [
    for v in var.pod_anti_affinity_preferred_during_scheduling_ignored_during_execution : {
      weight = v.weight
      podAffinityTerm = {
        labelSelector = v.pod_affinity_term.label_selector
        topologyKey   = v.pod_affinity_term.topology_key
      }
    }
  ]
}

resource "local_file" "values" {
  filename = "${var.path}/values.yaml"
  content = yamlencode({
    coder = {
      image = {
        repo        = var.image_repo
        tag         = var.image_tag
        pullPolicy  = var.image_pull_policy
        pullSecrets = var.image_pull_secrets
      }
      serviceAccount = {
        workspacePerms    = true
        enableDeployments = true
        name              = var.extern_prov_service_account_name
        disableCreate     = false
        annotations       = var.extern_prov_service_account_annotations
      }
      env = local.env_vars
      securityContext = {
        runAsNonRoot           = true
        runAsUser              = 1000
        runAsGroup             = 1000
        readOnlyRootFilesystem = null #Security Risk: should be false but leaving for now 
        seccompProfile = {
          type = "RuntimeDefault"
        }
        allowPrivilegeEscalation = false
      }
      resources = {
        requests = var.resource_requests
        limits   = var.resource_limits
      }
      nodeSelector              = var.node_selector
      replicaCount              = var.replica_count
      tolerations               = var.tolerations
      topologySpreadConstraints = local.topology_spread_constraints
      affinity = {
        podAntiAffinity = {
          preferredDuringSchedulingIgnoredDuringExecution = local.pod_anti_affinity_preferred
        }
      }
    }
  })
}

output "namespace" {
  description = "The Kubernetes namespace where Coder is deployed"
  value       = var.namespace
}

output "service_account_name" {
  description = "The name of the Kubernetes service account used by Coder"
  value       = var.service_account_name
}

output "external_provisioner_service_account_name" {
  description = "The name of the service account for external provisioner workspaces"
  value       = var.extern_prov_service_account_name
}

output "helm_chart_version" {
  description = "The version of the Coder Helm chart deployed"
  value       = var.coder_helm_chart_ver
}

output "replica_count" {
  description = "The number of Coder server replicas"
  value       = var.replica_count
}

output "primary_access_url" {
  description = "The primary URL for accessing Coder"
  value       = var.primary_access_url
}

output "manifest_path" {
  description = "The directory path where Kubernetes manifests are generated"
  value       = var.path
}