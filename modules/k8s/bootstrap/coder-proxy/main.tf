terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
      # Added version constraint for reproducibility and maintainability
      version = ">= 5.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "3.1.1"
    }
    kubernetes = {
      source = "hashicorp/kubernetes"
    }
    coderd = {
      source = "coder/coderd"
    }
    acme = {
      source = "vancluever/acme"
    }
    tls = {
      source = "hashicorp/tls"
    }
  }
}

##
# Coderd Inputs
##

variable "coder_proxy_name" {
  type = string
  validation {
    condition     = length(var.coder_proxy_name) > 0
    error_message = "Coder proxy name must not be empty"
  }
}

variable "coder_proxy_display_name" {
  type = string
  validation {
    condition     = length(var.coder_proxy_display_name) > 0
    error_message = "Coder proxy display name must not be empty"
  }
}

variable "coder_proxy_icon" {
  type = string
}

##
# TLS/SSL Inputs
##

variable "acme_registration_email" {
  type    = string
  default = ""
}

variable "acme_days_until_renewal" {
  type    = number
  default = 30
}

variable "acme_revoke_certificate" {
  type    = bool
  default = true
}

variable "cloudflare_api_token" {
  type      = string
  default   = ""
  sensitive = true
}


##
# Kubernetes Inputs
##

variable "namespace" {
  type = string
  validation {
    condition     = length(var.namespace) > 0
    error_message = "Namespace must not be empty"
  }
}

variable "helm_timeout" {
  type    = number
  default = 120 # In Seconds
}

variable "helm_version" {
  type    = string
  default = "2.25.1"
}

variable "image_repo" {
  type    = string
  default = "ghcr.io/coder/coder"
}

variable "image_tag" {
  type    = string
  default = "latest"
}

variable "image_pull_policy" {
  type    = string
  default = "IfNotPresent"
}

variable "image_pull_secrets" {
  type    = list(string)
  default = []
}

variable "replica_count" {
  type    = number
  default = 0
}

variable "env_vars" {
  type    = map(string)
  default = {}
}

variable "load_balancer_class" {
  type    = string
  default = "service.k8s.aws/nlb"
}

variable "resource_request" {
  type = object({
    cpu    = string
    memory = string
  })
  default = {
    cpu    = "250m"
    memory = "512Mi"
  }
}

variable "resource_limit" {
  type = object({
    cpu    = string
    memory = string
  })
  default = {
    cpu    = "500m"
    memory = "1Gi"
  }
}

variable "service_annotations" {
  type    = map(string)
  default = {}
}

variable "service_account_annotations" {
  type    = map(string)
  default = {}
}

variable "node_selector" {
  type    = map(string)
  default = {}
}

variable "tolerations" {
  type = list(object({
    key      = string
    operator = optional(string, "Equal")
    value    = string
    effect   = optional(string, "NoSchedule")
  }))
  default = []
}

variable "topology_spread_constraints" {
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
  type = string
  validation {
    condition     = can(regex("^https?://", var.primary_access_url))
    error_message = "Primary access URL must start with http:// or https://"
  }
}

variable "proxy_access_url" {
  type = string
  validation {
    condition     = can(regex("^https?://", var.proxy_access_url))
    error_message = "Proxy access URL must start with http:// or https://"
  }
}

variable "proxy_wildcard_url" {
  type = string
  validation {
    condition     = length(var.proxy_wildcard_url) > 0
    error_message = "Proxy wildcard URL must not be empty"
  }
}

variable "termination_grace_period_seconds" {
  type    = number
  default = 600
}

variable "ssl_cert_config" {
  type = object({
    name          = string
    create_secret = optional(bool, true)
  })
  default = {
    name          = "coder-proxy-tls"
    create_secret = true
  }
}

variable "proxy_token_config" {
  type = object({
    name = optional(string, "proxy-token")
    key  = optional(string, "proxy.key")
  })
  default = {
    name = "proxy-token"
    key  = "proxy.key"
  }
}


resource "coderd_workspace_proxy" "this" {
  name         = var.coder_proxy_name
  display_name = var.coder_proxy_display_name
  icon         = var.coder_proxy_icon
}

resource "kubernetes_namespace" "this" {
  metadata {
    name = var.namespace
  }
}

resource "kubernetes_secret" "coder-proxy-key" {
  metadata {
    name      = var.proxy_token_config.name
    namespace = kubernetes_namespace.this.metadata[0].name
  }
  data = {
    "${var.proxy_token_config.key}" = coderd_workspace_proxy.this.session_token
  }
  type = "Opaque"
}

locals {
  common_name = trimprefix(trimprefix(var.proxy_access_url, "https://"), "http://")
}

module "acme-cloudflare-ssl" {
  source = "../acme-cloudflare-ssl"
  count  = var.ssl_cert_config.create_secret ? 1 : 0

  dns_names               = [local.common_name, var.proxy_wildcard_url]
  common_name             = local.common_name
  kubernetes_secret_name  = var.ssl_cert_config.name
  kubernetes_namespace    = kubernetes_namespace.this.metadata[0].name
  acme_registration_email = var.acme_registration_email
  acme_days_until_renewal = var.acme_days_until_renewal
  acme_revoke_certificate = var.acme_revoke_certificate
  cloudflare_api_token    = var.cloudflare_api_token
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
          name = kubernetes_secret.coder-proxy-key.metadata[0].name
          key  = var.proxy_token_config.key
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
        # Removed try() - topologyKey is required string field
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

resource "helm_release" "coder-proxy" {
  name             = "coder-v2"
  namespace        = kubernetes_namespace.this.metadata[0].name
  chart            = "coder"
  repository       = "https://helm.coder.com/v2"
  create_namespace = false
  upgrade_install  = true
  skip_crds        = false
  wait             = true
  wait_for_jobs    = true
  version          = var.helm_version
  timeout          = var.helm_timeout

  # Ensure secrets exist before helm install
  depends_on = [kubernetes_secret.coder-proxy-key]

  lifecycle {
    # Recreate on version change for clean upgrades
    create_before_destroy = true
  }

  values = [yamlencode({
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
        # Use try() to handle conditional module reference safely
        secretNames = [
          var.ssl_cert_config.create_secret ?
          try(module.acme-cloudflare-ssl[0].kubernetes_secret_name, var.ssl_cert_config.name) :
          var.ssl_cert_config.name
        ]
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
  })]
}