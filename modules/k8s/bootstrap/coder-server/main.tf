terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "2.17.0"
    }
    kubernetes = {
      source = "hashicorp/kubernetes"
    }
    acme = {
      source = "vancluever/acme"
    }
    tls = {
      source = "hashicorp/tls"
    }
  }
}

variable "cluster_name" {
  type = string
}

variable "cluster_oidc_provider_arn" {
  type = string
}

variable "policy_resource_region" {
  type    = string
  default = ""
}

variable "policy_resource_account" {
  type    = string
  default = ""
}

variable "policy_name" {
  type    = string
  default = ""
}

variable "role_name" {
  type    = string
  default = ""
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
  type = string
  # Default is latest for convenience but should be overridden with specific version in production for reproducibility
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
  type = number
  # reverted back to 0 as this is a demo deployment by default
  default = 0
}

variable "env_vars" {
  type    = map(string)
  default = {}
}

variable "load_balancer_class" {
  type    = string
  default = "service.k8s.aws/nlb"
  # Added validation because invalid load balancer class causes Kubernetes service errors
  validation {
    # Validation checks for empty string which is sufficient for this use case
    condition     = var.load_balancer_class != ""
    error_message = "load_balancer_class must not be empty."
  }
}

variable "resource_request" {
  type = object({
    cpu    = string
    memory = string
  })
  default = {
    cpu    = "2000m"
    memory = "4Gi"
  }
}

variable "resource_limit" {
  type = object({
    cpu    = string
    memory = string
  })
  default = {
    cpu    = "4000m"
    memory = "8Gi"
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
}

variable "wildcard_access_url" {
  type = string
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
    name          = "coder-tls"
    create_secret = true
  }
}


variable "db_secret_name" {
  type    = string
  default = "postgres"
}

variable "db_secret_key" {
  type    = string
  default = "url"
}

variable "db_secret_url" {
  type      = string
  sensitive = true
}

variable "oidc_config" {
  type = object({
    sign_in_text = string
    icon_url     = string
    scopes       = list(string)
    email_domain = string
  })
}

variable "oidc_secret_name" {
  type    = string
  default = "oidc"
}

variable "oidc_secret_issuer_url_key" {
  type    = string
  default = "issuer-url"
}

variable "oidc_secret_issuer_url" {
  type      = string
  sensitive = true
}

variable "oidc_secret_client_id_key" {
  type    = string
  default = "client-id"
}

variable "oidc_secret_client_id" {
  type      = string
  sensitive = true
}

variable "oidc_secret_client_secret_key" {
  type    = string
  default = "client-secret"
}

variable "oidc_secret_client_secret" {
  type      = string
  sensitive = true
}

variable "oauth_secret_name" {
  type    = string
  default = "oauth"
}

variable "oauth_secret_client_id_key" {
  type    = string
  default = "client-id"
}

variable "oauth_secret_client_id" {
  type      = string
  sensitive = true
}

variable "oauth_secret_client_secret_key" {
  type    = string
  default = "client-secret"
}

variable "oauth_secret_client_secret" {
  type      = string
  sensitive = true
}

variable "github_external_auth_config" {
  type = object({
    id   = string
    type = optional(string, "github")
  })
  default = {
    id   = "primary-github"
    type = "github"
  }
}

variable "github_external_auth_secret_name" {
  type    = string
  default = "github-external-auth"
}

variable "github_external_auth_secret_client_id_key" {
  type    = string
  default = "client-id"
}

variable "github_external_auth_secret_client_id" {
  type      = string
  sensitive = true
}

variable "github_external_auth_secret_client_secret_key" {
  type    = string
  default = "client-secret"
}

variable "github_external_auth_secret_client_secret" {
  type      = string
  sensitive = true
}

variable "coder_builtin_provisioner_count" {
  type    = number
  default = 3
}

variable "coder_experiments" {
  type    = list(string)
  default = []
}

variable "coder_github_allowed_orgs" {
  type    = list(string)
  default = []
}

variable "coder_enable_terraform_debug_mode" {
  # Debug mode should be disabled in production for performance
  type    = bool
  default = false
}

variable "coder_trace_logs" {
  # Trace logs should be disabled in production for performance
  type    = bool
  default = false
}

variable "coder_log_filter" {
  # Log filter should be more restrictive in production for performance
  type    = string
  default = "info"
}

variable "tags" {
  type    = map(string)
  default = {}
}

data "aws_region" "this" {}

data "aws_caller_identity" "this" {}

locals {
  github_allow_everyone = length(var.coder_github_allowed_orgs) == 0
  # Cache GitHub config key and value to avoid repeated conditional evaluation for performance
  github_config_key   = local.github_allow_everyone ? "CODER_OAUTH2_GITHUB_ALLOW_EVERYONE" : "CODER_OAUTH2_GITHUB_ALLOWED_ORGS"
  github_config_value = local.github_allow_everyone ? "true" : join(",", var.coder_github_allowed_orgs)

  primary_env_vars = {
    CODER_ACCESS_URL             = var.primary_access_url
    CODER_WILDCARD_ACCESS_URL    = var.wildcard_access_url
    CODER_REDIRECT_TO_ACCESS_URL = true
    CODER_PG_AUTH                = "password"

    CODER_OIDC_SIGN_IN_TEXT = var.oidc_config.sign_in_text
    CODER_OIDC_ICON_URL     = var.oidc_config.icon_url
    CODER_OIDC_SCOPES       = join(",", var.oidc_config.scopes)
    CODER_OIDC_EMAIL_DOMAIN = var.oidc_config.email_domain

    CODER_OAUTH2_GITHUB_DEFAULT_PROVIDER_ENABLE = false
    CODER_OAUTH2_GITHUB_ALLOW_SIGNUPS           = true
    CODER_OAUTH2_GITHUB_DEVICE_FLOW             = false
    "${local.github_config_key}"                = local.github_config_value

    CODER_EXTERNAL_AUTH_0_ID   = var.github_external_auth_config.id
    CODER_EXTERNAL_AUTH_0_TYPE = var.github_external_auth_config.type

    # Made configurable for production performance optimization
    CODER_ENABLE_TERRAFORM_DEBUG_MODE = var.coder_enable_terraform_debug_mode
    CODER_TRACE_LOGS                  = var.coder_trace_logs
    CODER_LOG_FILTER                  = var.coder_log_filter
    CODER_SWAGGER_ENABLE              = true
    CODER_UPDATE_CHECK                = true
    CODER_CLI_UPGRADE_MESSAGE         = true

    CODER_PROVISIONER_DAEMONS               = var.coder_builtin_provisioner_count
    CODER_PROVISIONER_FORCE_CANCEL_INTERVAL = "10m0s"
    CODER_QUIET_HOURS_DEFAULT_SCHEDULE      = "CRON_TZ=America/Los_Angeles 50 23 * * *"
    CODER_ALLOW_CUSTOM_QUIET_HOURS          = true

    CODER_PROMETHEUS_ENABLE              = true
    CODER_PROMETHEUS_COLLECT_AGENT_STATS = true
    CODER_PROMETHEUS_COLLECT_DB_METRICS  = true

    # Experimental Coder Features
    CODER_EXPERIMENTS = join(",", var.coder_experiments)
    # Needed by the ai-tasks experiment to embed workspace apps running on subdomains in iframes
    CODER_ADDITIONAL_CSP_POLICY = "frame-src ${var.primary_access_url}"
  }
  env_vars = concat([
    for k, v in merge(local.primary_env_vars, var.env_vars) : { name = k, value = tostring(v) }
    ], [{
      name = "CODER_PG_CONNECTION_URL"
      valueFrom = {
        secretKeyRef = {
          name = var.db_secret_name
          key  = var.db_secret_key
        }
      }
      }, {
      name = "CODER_OIDC_ISSUER_URL"
      valueFrom = {
        secretKeyRef = {
          name = var.oidc_secret_name
          key  = var.oidc_secret_issuer_url_key
        }
      }
      }, {
      name = "CODER_OIDC_CLIENT_ID"
      valueFrom = {
        secretKeyRef = {
          name = var.oidc_secret_name
          key  = var.oidc_secret_client_id_key
        }
      }
      }, {
      name = "CODER_OIDC_CLIENT_SECRET"
      valueFrom = {
        secretKeyRef = {
          name = var.oidc_secret_name
          key  = var.oidc_secret_client_secret_key
        }
      }
      }, {
      name = "CODER_OAUTH2_GITHUB_CLIENT_ID"
      valueFrom = {
        secretKeyRef = {
          name = var.oauth_secret_name
          key  = var.oauth_secret_client_id_key
        }
      }
      }, {
      name = "CODER_OAUTH2_GITHUB_CLIENT_SECRET"
      valueFrom = {
        secretKeyRef = {
          name = var.oauth_secret_name
          key  = var.oauth_secret_client_secret_key
        }
      }
      }, {
      name = "CODER_EXTERNAL_AUTH_0_CLIENT_ID"
      valueFrom = {
        secretKeyRef = {
          name = var.github_external_auth_secret_name
          key  = var.github_external_auth_secret_client_id_key
        }
      }
      }, {
      name = "CODER_EXTERNAL_AUTH_0_CLIENT_SECRET"
      valueFrom = {
        secretKeyRef = {
          name = var.github_external_auth_secret_name
          key  = var.github_external_auth_secret_client_secret_key
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

locals {
  region      = var.policy_resource_region == "" ? data.aws_region.this.region : var.policy_resource_region
  account_id  = var.policy_resource_account == "" ? data.aws_caller_identity.this.account_id : var.policy_resource_account
  policy_name = var.policy_name == "" ? "Server-${data.aws_region.this.region}" : var.policy_name
  role_name   = var.role_name == "" ? "server-${data.aws_region.this.region}" : var.role_name
}

module "provisioner-policy" {
  count       = var.coder_builtin_provisioner_count == 0 ? 0 : 1
  source      = "../../../security/policy"
  name        = local.policy_name
  path        = "/"
  description = "Coder Terraform External Provisioner Policy"
  policy_json = data.aws_iam_policy_document.provisioner-policy.json
}

module "provisioner-oidc-role" {
  count        = var.coder_builtin_provisioner_count == 0 ? 0 : 1
  source       = "../../../security/role/access-entry"
  name         = local.role_name
  cluster_name = var.cluster_name
  policy_arns = {
    "AmazonEC2ReadOnlyAccess" = "arn:aws:iam::aws:policy/AmazonEC2ReadOnlyAccess"
    "TFProvisionerPolicy"     = module.provisioner-policy[0].policy_arn
  }
  cluster_policy_arns = {}
  oidc_principals = {
    "${var.cluster_oidc_provider_arn}" = ["system:serviceaccount:*:*"]
  }
  tags = var.tags
}

resource "kubernetes_namespace" "this" {
  metadata {
    name = var.namespace
  }
}

resource "helm_release" "coder-server" {
  name             = "coder"
  namespace        = kubernetes_namespace.this.metadata[0].name
  chart            = "coder"
  repository       = "https://helm.coder.com/v2"
  create_namespace = false
  skip_crds        = false
  wait             = true
  wait_for_jobs    = true
  version          = var.helm_version
  timeout          = var.helm_timeout

  # Ensure secrets exist before helm install
  depends_on = [
    kubernetes_secret.pg-connection,
    kubernetes_secret.oidc,
    kubernetes_secret.oauth,
    kubernetes_secret.external_auth
  ]

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
      env = local.env_vars
      tls = {
        secretNames = [var.ssl_cert_config.name]
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
        annotations = var.coder_builtin_provisioner_count == 0 ? var.service_account_annotations : merge({
          "eks.amazonaws.com/role-arn" : module.provisioner-oidc-role[0].role_arn
        }, var.service_account_annotations)
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

resource "kubernetes_secret" "pg-connection" {
  metadata {
    name      = var.db_secret_name
    namespace = kubernetes_namespace.this.metadata[0].name
  }
  data = {
    "${var.db_secret_key}" = var.db_secret_url
  }
  type = "Opaque"
}

resource "kubernetes_secret" "oidc" {
  metadata {
    name      = var.oidc_secret_name
    namespace = kubernetes_namespace.this.metadata[0].name
  }
  data = {
    "${var.oidc_secret_issuer_url_key}"    = var.oidc_secret_issuer_url
    "${var.oidc_secret_client_id_key}"     = var.oidc_secret_client_id
    "${var.oidc_secret_client_secret_key}" = var.oidc_secret_client_secret
  }
  type = "Opaque"
}

resource "kubernetes_secret" "oauth" {
  metadata {
    name      = var.oauth_secret_name
    namespace = kubernetes_namespace.this.metadata[0].name
  }
  data = {
    "${var.oauth_secret_client_id_key}"     = var.oauth_secret_client_id
    "${var.oauth_secret_client_secret_key}" = var.oauth_secret_client_secret
  }
  type = "Opaque"
}

resource "kubernetes_secret" "external_auth" {
  metadata {
    name      = var.github_external_auth_secret_name
    namespace = kubernetes_namespace.this.metadata[0].name
  }
  data = {
    "${var.github_external_auth_secret_client_id_key}"     = var.github_external_auth_secret_client_id
    "${var.github_external_auth_secret_client_secret_key}" = var.github_external_auth_secret_client_secret
  }
  type = "Opaque"
}

locals {
  common_name   = trimprefix(trimprefix(var.primary_access_url, "https://"), "http://")
  wildcard_name = trimprefix(trimprefix(var.wildcard_access_url, "https://"), "http://")
}

module "acme-cloudflare-ssl" {
  source = "../acme-cloudflare-ssl"
  count  = var.ssl_cert_config.create_secret ? 1 : 0

  dns_names               = [local.common_name, local.wildcard_name]
  common_name             = local.common_name
  kubernetes_secret_name  = var.ssl_cert_config.name
  kubernetes_namespace    = kubernetes_namespace.this.metadata[0].name
  acme_registration_email = var.acme_registration_email
  acme_days_until_renewal = var.acme_days_until_renewal
  acme_revoke_certificate = var.acme_revoke_certificate
  cloudflare_api_token    = var.cloudflare_api_token
}