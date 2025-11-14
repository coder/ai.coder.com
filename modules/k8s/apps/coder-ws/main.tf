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
  description = "Kubernetes namespace where Coder workspace provisioners will be deployed"
  type        = string
  validation {
    condition     = length(var.namespace) > 0
    error_message = "Namespace must not be empty"
  }
}

variable "image_repo" {
  description = "Container image repository for Coder provisioner"
  type        = string
  validation {
    condition     = length(var.image_repo) > 0
    error_message = "Image repository must not be empty"
  }
}

variable "image_tag" {
  description = "Container image tag for Coder provisioner"
  type        = string
  validation {
    condition     = length(var.image_tag) > 0
    error_message = "Image tag must not be empty"
  }
}

variable "image_pull_policy" {
  description = "Image pull policy for Coder provisioner container (Always, IfNotPresent, or Never)"
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

variable "coder_provisioner_helm_version" {
  description = "Version of the Coder provisioner Helm chart to deploy"
  type        = string
  default     = "2.23.0"
  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.coder_provisioner_helm_version))
    error_message = "Helm chart version must be in semver format (e.g., 2.23.0)"
  }
}

variable "coder_logstream_kube_version" {
  description = "Version of the Coder logstream-kube Helm chart to deploy"
  type        = string
  default     = "0.0.11"
  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.coder_logstream_kube_version))
    error_message = "Helm chart version must be in semver format (e.g., 0.0.11)"
  }
}

variable "primary_access_url" {
  description = "Primary URL for accessing Coder"
  type        = string
  validation {
    condition     = can(regex("^https?://", var.primary_access_url))
    error_message = "Primary access URL must start with http:// or https://"
  }
}

variable "service_account_name" {
  description = "Name of the Kubernetes service account for Coder provisioner"
  type        = string
  validation {
    condition     = length(var.service_account_name) > 0
    error_message = "Service account name must not be empty"
  }
}

variable "service_account_labels" {
  description = "Labels to apply to the Coder provisioner service account"
  type        = map(string)
  default     = {}
}

variable "service_account_annotations" {
  description = "Annotations to apply to the Coder provisioner service account"
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
  description = "Number of Coder provisioner replicas to run (0 for external provisioners)"
  type        = number
  default     = 0
  validation {
    condition     = var.replica_count >= 0
    error_message = "Replica count must be non-negative"
  }
}

variable "env_vars" {
  description = "Additional environment variables for Coder provisioner"
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
    cpu    = "250m"
    memory = "512Mi"
  }
  validation {
    condition     = can(regex("^[0-9]+(\\.[0-9]+)?(m|[KMGT]i?)?$", var.resource_requests.cpu))
    error_message = "CPU must be in Kubernetes format (e.g., 250m, 0.25, 1)"
  }
  validation {
    condition     = can(regex("^[0-9]+(\\.[0-9]+)?([EPTGMK]i?)?$", var.resource_requests.memory))
    error_message = "Memory must be in Kubernetes format (e.g., 512Mi, 1Gi)"
  }
}

variable "resource_limits" {
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
    condition     = can(regex("^[0-9]+(\\.[0-9]+)?(m|[KMGT]i?)?$", var.resource_limits.cpu))
    error_message = "CPU must be in Kubernetes format (e.g., 500m, 0.5, 1)"
  }
  validation {
    condition     = can(regex("^[0-9]+(\\.[0-9]+)?([EPTGMK]i?)?$", var.resource_limits.memory))
    error_message = "Memory must be in Kubernetes format (e.g., 1Gi, 1024Mi)"
  }
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

variable "provisioner_secret" {
  description = "Configuration for the Coder provisioner authentication secret"
  type = object({
    key_secret_name                  = string
    key_secret_key                   = string
    key_secret_path                  = string
    termination_grace_period_seconds = optional(number, 600)
  })
  sensitive = true
}

variable "kustomize_resources" {
  description = "Additional Kubernetes resources to include in kustomization"
  type        = list(string)
  default     = []
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

locals {
  patches = [for v in var.patches : {
    patch  = v.expected
    target = v.target
  }]
}

module "kustomization" {
  source    = "../../objects/kustomization"
  namespace = var.namespace
  helm_charts = [{
    name         = "coder-provisioner"
    release_name = "coder-provisioner"
    repo         = "https://helm.coder.com/v2"
    namespace    = var.namespace
    include_crds = true
    version      = var.coder_provisioner_helm_version
    values_file  = "./values.yaml"
    }, {
    name         = "coder-logstream-kube"
    release_name = "coder-logstream-kube"
    repo         = "https://helm.coder.com/logstream-kube"
    namespace    = var.namespace
    include_crds = true
    version      = var.coder_logstream_kube_version
    values_inline = {
      url = var.primary_access_url
    }
  }]
  secret_generator = [{
    name      = var.provisioner_secret.key_secret_name
    namespace = var.namespace
    behavior  = "create"
    files = [
      join("/", [
        var.provisioner_secret.key_secret_path,
        var.provisioner_secret.key_secret_key
      ])
    ]
    options = {
      disable_name_suffix_hash = true
    }
  }]
  patches = local.patches
  resources = concat([
    "namespace.yaml",
    "serviceaccount.yaml"
  ], var.kustomize_resources)
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
        readOnlyRootFilesystem = null
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
    provisionerDaemon = {
      keySecretKey                  = var.provisioner_secret.key_secret_key
      keySecretName                 = var.provisioner_secret.key_secret_name
      terminationGracePeriodSeconds = var.provisioner_secret.termination_grace_period_seconds
    }
  })
}

output "namespace" {
  description = "The Kubernetes namespace where Coder workspace provisioners are deployed"
  value       = var.namespace
}

output "service_account_name" {
  description = "The name of the Kubernetes service account used by Coder provisioner"
  value       = var.service_account_name
}

output "external_provisioner_service_account_name" {
  description = "The name of the service account for external provisioner workspaces"
  value       = var.extern_prov_service_account_name
}

output "provisioner_helm_version" {
  description = "The version of the Coder provisioner Helm chart deployed"
  value       = var.coder_provisioner_helm_version
}

output "logstream_kube_version" {
  description = "The version of the Coder logstream-kube Helm chart deployed"
  value       = var.coder_logstream_kube_version
}

output "replica_count" {
  description = "The number of Coder provisioner replicas configured"
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