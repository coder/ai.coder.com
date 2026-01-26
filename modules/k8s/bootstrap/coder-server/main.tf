terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.17.0"
    }
    kubernetes = {
      source = "hashicorp/kubernetes"
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
  default = 300 # In Seconds
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
    caissuer        = optional(string, "issuer")
    secretissuer    = optional(string, "issuer")
    create_secret = optional(bool, true)
  })
  default = {
    name          = "coder-tls"
    caissuer        = "issuer"
    secretissuer        = "issuer"
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

variable "enable_oidc" {
  type = bool
  default = true
}

variable "oidc_config" {
  type = object({
    sign_in_text = string
    icon_url     = string
    scopes       = list(string)
    email_domain = string
  })
  default = {
    sign_in_text = ""
    icon_url     = ""
    scopes       = []
    email_domain = ""
  }
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
  default = ""
}

variable "oidc_secret_client_id_key" {
  type    = string
  default = "client-id"
}

variable "oidc_secret_client_id" {
  type      = string
  sensitive = true
  default = ""
}

variable "oidc_secret_client_secret_key" {
  type    = string
  default = "client-secret"
}

variable "oidc_secret_client_secret" {
  type      = string
  sensitive = true
  default = ""
}

variable "enable_oauth" {
  type = bool
  default = true
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
  default = ""
}

variable "oauth_secret_client_secret_key" {
  type    = string
  default = "client-secret"
}

variable "oauth_secret_client_secret" {
  type      = string
  sensitive = true
  default = ""
}

variable "enable_github_external_auth" {
  type = bool
  default = true
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
  default = ""
}

variable "github_external_auth_secret_client_secret_key" {
  type    = string
  default = "client-secret"
}

variable "github_external_auth_secret_client_secret" {
  type      = string
  sensitive = true
  default = ""
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

variable "openai_llm_endpoint" {
  type      = string
  sensitive = true
  default   = ""
}

variable "openai_llm_secret_name" {
  type    = string
  default = "coder-openai-llm-key"
}

variable "openai_llm_key" {
  type      = string
  sensitive = true
  default   = ""
}

variable "anthropic_llm_endpoint" {
  type      = string
  sensitive = true
  default   = ""
}

variable "anthropic_llm_secret_name" {
  type    = string
  default = "coder-anthropic-llm-key"
}

variable "anthropic_llm_key" {
  type      = string
  sensitive = true
  default   = ""
}

variable "tags" {
  type    = map(string)
  default = {}
}

data "aws_region" "this" {}

data "aws_caller_identity" "this" {}

locals {
  oidc_secret_issuer_url = var.enable_oidc ? {
    name = "CODER_OIDC_ISSUER_URL"
    valueFrom = {
      secretKeyRef = {
        name = var.oidc_secret_name
        key  = var.oidc_secret_issuer_url_key
      }
    }
  } : null
  oidc_client_id = var.enable_oidc ? {
    name = "CODER_OIDC_CLIENT_ID"
    valueFrom = {
      secretKeyRef = {
        name = var.oidc_secret_name
        key  = var.oidc_secret_client_id_key
      }
    }
  } : null
  oidc_client_secret = var.enable_oidc ? {
    name = "CODER_OIDC_CLIENT_SECRET"
    valueFrom = {
      secretKeyRef = {
        name = var.oidc_secret_name
        key  = var.oidc_secret_client_secret_key
      }
    }
  } : null
  oauth2_github_client_id = var.enable_oauth ? {
    name = "CODER_OAUTH2_GITHUB_CLIENT_ID"
    valueFrom = {
      secretKeyRef = {
        name = var.oauth_secret_name
        key  = var.oauth_secret_client_id_key
      }
    }
  } : null
  oauth2_github_client_secret = var.enable_oauth ? {
    name = "CODER_OAUTH2_GITHUB_CLIENT_SECRET"
    valueFrom = {
      secretKeyRef = {
        name = var.oauth_secret_name
        key  = var.oauth_secret_client_secret_key
      }
    }
  } : null
  external_auth_github_client_id = var.enable_github_external_auth ? {
    name = "CODER_EXTERNAL_AUTH_0_CLIENT_ID"
    valueFrom = {
      secretKeyRef = {
        name = var.oauth_secret_name
        key  = var.oauth_secret_client_id_key
      }
    }
  } : null
  external_auth_github_client_secret = var.enable_github_external_auth ? {
    name = "CODER_EXTERNAL_AUTH_0_CLIENT_SECRET"
    valueFrom = {
      secretKeyRef = {
        name = var.oauth_secret_name
        key  = var.oauth_secret_client_secret_key
      }
    }
  } : null
}

locals {
  github_allow_everyone = length(var.coder_github_allowed_orgs) == 0
  primary_env_vars = merge({
    CODER_ACCESS_URL             = var.primary_access_url
    CODER_WILDCARD_ACCESS_URL    = var.wildcard_access_url
    CODER_REDIRECT_TO_ACCESS_URL = true
    CODER_PG_AUTH                = "password"

    CODER_ENABLE_TERRAFORM_DEBUG_MODE = true
    CODER_TRACE_LOGS                  = true
    CODER_LOG_FILTER                  = ".*"
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
    # CODER_PROMETHEUS_ADDRESS             = "127.0.0.1:${var.prometheus_port}"

    # CODER_AIBRIDGE_BEDROCK_MODEL = "global.anthropic.claude-sonnet-4-5-20250929-v1:0"
    # CODER_AIBRIDGE_BEDROCK_SMALL_FAST_MODEL = "global.anthropic.claude-haiku-4-5-20251001-v1:0"

    # Experimental Coder Features
    # CODER_EXPERIMENTS = join(",", var.coder_experiments)
    # Needed by the ai-tasks experiment to embed workspace apps running on subdomains in iframes
    CODER_ADDITIONAL_CSP_POLICY = "frame-src ${var.primary_access_url}"
  }, merge(var.enable_oidc ? {
    CODER_OIDC_SIGN_IN_TEXT = var.oidc_config.sign_in_text
    CODER_OIDC_ICON_URL     = var.oidc_config.icon_url
    CODER_OIDC_SCOPES       = join(",", var.oidc_config.scopes)
    CODER_OIDC_EMAIL_DOMAIN = var.oidc_config.email_domain
  } : {}, merge(var.enable_oauth ? {
    CODER_OAUTH2_GITHUB_DEFAULT_PROVIDER_ENABLE                                                                  = false
    CODER_OAUTH2_GITHUB_ALLOW_SIGNUPS                                                                            = true
    CODER_OAUTH2_GITHUB_DEVICE_FLOW                                                                              = false
    "${local.github_allow_everyone ? "CODER_OAUTH2_GITHUB_ALLOW_EVERYONE" : "CODER_OAUTH2_GITHUB_ALLOWED_ORGS"}" = "${local.github_allow_everyone ? "true" : join(",", var.coder_github_allowed_orgs)}"
  } : {}, var.enable_github_external_auth ? {
    CODER_EXTERNAL_AUTH_0_ID   = "primary-github"
    CODER_EXTERNAL_AUTH_0_TYPE = "github"
  } : {})))
  env_vars = concat([
    for k, v in merge(local.primary_env_vars, var.env_vars) : { name = k, value = tostring(v) }
    ], concat([{
      name = "CODER_PG_CONNECTION_URL"
      valueFrom = {
        secretKeyRef = {
          name = var.db_secret_name
          key  = var.db_secret_key
        }
      }
      }, 
      # local.oidc_secret_issuer_url,
      # local.oidc_client_id, 
      # local.oidc_client_secret, 
      # local.oauth2_github_client_id, 
      # local.oauth2_github_client_secret, 
      # local.external_auth_github_client_id, 
      # local.external_auth_github_client_secret,
      ], concat(var.anthropic_llm_endpoint != "" ? [{
        name = "CODER_AIBRIDGE_ANTHROPIC_KEY"
        valueFrom = {
          secretKeyRef = {
            name = kubernetes_secret.anthropic-llm-secret[0].metadata[0].name
            key  = "key"
          }
        }
        }, {
        name = "CODER_AIBRIDGE_ANTHROPIC_BASE_URL"
        valueFrom = {
          secretKeyRef = {
            name = kubernetes_secret.anthropic-llm-secret[0].metadata[0].name
            key  = "base_url"
          }
        }
      }] : [],
      var.openai_llm_endpoint != "" ? [{
        name = "CODER_AIBRIDGE_OPENAI_KEY"
        valueFrom = {
          secretKeyRef = {
            name = kubernetes_secret.openai-llm-secret[0].metadata[0].name
            key  = "key"
          }
        }
        }, {
        name = "CODER_AIBRIDGE_OPENAI_BASE_URL"
        valueFrom = {
          secretKeyRef = {
            name = kubernetes_secret.openai-llm-secret[0].metadata[0].name
            key  = "base_url"
          }
        }
  }] : [])))
  pod_anti_affinity_preferred_during_scheduling_ignored_during_execution = [
    for k, v in var.pod_anti_affinity_preferred_during_scheduling_ignored_during_execution : {
      weight = v.weight
      podAffinityTerm = {
        labelSelector = {
          matchLabels = try(v.pod_affinity_term.label_selector.match_labels, {})
        }
        topologyKey = try(v.pod_affinity_term.topology_key, {})
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
  policy_name = var.policy_name == "" ? "coder-srv" : var.policy_name
  role_name   = var.role_name == "" ? "coder-srv" : var.role_name
}

module "provisioner-policy" {
  count       = var.coder_builtin_provisioner_count == 0 ? 0 : 1
  source      = "../../../security/policy"
  name        = local.policy_name
  path         = "/${var.cluster_name}/${data.aws_region.this.region}/"
  description = "Coder Terraform External Provisioner Policy"
  policy_json = data.aws_iam_policy_document.provisioner-policy.json
}

module "provisioner-oidc-role" {
  count        = var.coder_builtin_provisioner_count == 0 ? 0 : 1
  source       = "../../../security/role/access-entry"
  name         = local.role_name
  path         = "/${var.cluster_name}/${data.aws_region.this.region}/"
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

locals {
  ssl_vol_friendly_name = replace(var.ssl_cert_config.name, ".", "-")
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

resource "kubernetes_secret" "openai-llm-secret" {
  count = var.openai_llm_endpoint != "" ? 1 : 0
  metadata {
    name      = var.openai_llm_secret_name
    namespace = kubernetes_namespace.this.metadata[0].name
  }
  data = {
    base_url = var.openai_llm_endpoint
    key      = var.openai_llm_key
  }
  type = "Opaque"
}

resource "kubernetes_secret" "anthropic-llm-secret" {
  count = var.anthropic_llm_endpoint != "" ? 1 : 0
  metadata {
    name      = var.anthropic_llm_secret_name
    namespace = kubernetes_namespace.this.metadata[0].name
  }
  data = {
    base_url = var.anthropic_llm_endpoint
    key      = var.anthropic_llm_key
  }
  type = "Opaque"
}

locals {
  common_name   = trimprefix(trimprefix(var.primary_access_url, "https://"), "http://")
  wildcard_name = trimprefix(trimprefix(var.wildcard_access_url, "https://"), "http://")
  cert_refresh_interval = "2160h" # 90 days
  cert_renew_before = "360h" # 15 days
  secret_refresh_interval = "1812h0m0s" # 75.5 days
  tls_secret_key = "tls.key"
  tls_secret_crt = "tls.crt"
  tls_remote_key = "tls-${local.common_name}.key"
  tls_remote_crt = "tls-${local.common_name}.crt"
}

resource "kubernetes_manifest" "pull" {

  field_manager {
    force_conflicts = true
  }

  wait {
    fields = {
      "status.conditions[0].type" = "Ready"
    }
  }
  
  timeouts {
    create = "1m"
    update = "1m"
    delete = "30s"
  }

  manifest = {
    apiVersion = "external-secrets.io/v1"
    kind = "ExternalSecret"
    metadata = {
      name = var.ssl_cert_config.name 
      namespace = kubernetes_namespace.this.metadata[0].name
    }
    spec = {
      secretStoreRef = {
        kind = "ClusterSecretStore"
        name = var.ssl_cert_config.secretissuer
      }
      refreshPolicy = "Periodic"
      refreshInterval = local.secret_refresh_interval
      target = {
        name = local.ssl_vol_friendly_name
        creationPolicy = "Orphan"
        deletionPolicy = "Retain"
        template = {
          type = "kubernetes.io/tls"
          metadata = {
            labels = {
              "controller.cert-manager.io/fao" = "true"
            }
            annotations = {
              "cert-manager.io/alt-names" = "${local.wildcard_name},${local.common_name}"                                                                                                                                
              "cert-manager.io/certificate-name" = var.ssl_cert_config.name                                                                                     
              "cert-manager.io/common-name" = local.common_name 
              "cert-manager.io/ip-sans" = ""
              "cert-manager.io/issuer-group" = ""                                                                                                                   
              "cert-manager.io/issuer-kind" = "ClusterIssuer"                                                                                               
              "cert-manager.io/issuer-name" = var.ssl_cert_config.caissuer
              "cert-manager.io/uri-sans" = ""
            }
          }
        }
      }
      data = [{
        secretKey = local.tls_secret_crt
        remoteRef = {
          key = local.tls_remote_crt
        }
      },{
        secretKey = local.tls_secret_key
        remoteRef = {
          key = local.tls_remote_key
        }
      }]
    }
  }
}

resource "time_sleep" "wait" {
  # Let the secret create first if it exists in AWS Secrets Manager.
  depends_on = [ kubernetes_manifest.pull ]
  create_duration = "30s"
}

## 
# Requires the cert-manager
## 

resource "kubernetes_manifest" "certificate" {

  depends_on = [ time_sleep.wait ]

  field_manager {
    force_conflicts = true
  }

  wait {
    condition {
      type   = "Ready"
      status = "True"
    }
  }

  timeouts {
    create = "10m"
    update = "10m"
    delete = "30s"
  }

  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind = "Certificate"
    metadata = {
      name = var.ssl_cert_config.name
      namespace = kubernetes_namespace.this.metadata[0].name
    }
    spec = {
      commonName = local.common_name
      dnsNames = [
        local.common_name,
        local.wildcard_name
      ]
      duration = local.cert_refresh_interval
      renewBefore = local.cert_renew_before
      issuerRef = {
        kind = "ClusterIssuer"
        name = var.ssl_cert_config.caissuer
      }
      secretName = local.ssl_vol_friendly_name
      privateKey = {
        rotationPolicy = "Never"
        algorithm = "RSA"
        encoding = "PKCS1"
        size = "2048"
      }
    }
  }
}

resource "kubernetes_manifest" "push" {

  depends_on = [ kubernetes_manifest.certificate ]

  field_manager {
    force_conflicts = true
  }

  wait {
    condition {
      type   = "Ready"
      status = "True"
    }
  }

  timeouts {
    create = "10m"
    update = "10m"
    delete = "30s"
  }

  manifest = {
    apiVersion = "external-secrets.io/v1alpha1"
    kind = "PushSecret"
    metadata = {
      name = var.ssl_cert_config.name 
      namespace = kubernetes_namespace.this.metadata[0].name
    }
    spec = {
      updatePolicy = "Replace"
      deletionPolicy = "None"
      refreshInterval = local.secret_refresh_interval
      secretStoreRefs = [{
        kind = "ClusterSecretStore"
        name = var.ssl_cert_config.secretissuer
      }]
      selector = {
        secret = {
          name = kubernetes_manifest.certificate.manifest.spec.secretName
        } 
      }
      data = [{
        match = {
          secretKey = local.tls_secret_crt
          remoteRef = {
            remoteKey = local.tls_remote_crt
          }
        }
      },{
        match = {
          secretKey = local.tls_secret_key
          remoteRef = {
            remoteKey = local.tls_remote_key
          }
        }
      }]
    }
  }
}

resource "kubernetes_service" "prometheus" {
  metadata {
    name      = "coder-prometheus"
    namespace = kubernetes_namespace.this.metadata[0].name
    # labels    = local.app_labels
  }
  spec {
    type       = "ClusterIP"
    cluster_ip = "None"
    port {
      name        = "prom-http"
      protocol    = "TCP"
      port        = 2112
      target_port = 2112
    }
    selector = {
      "app.kubernetes.io/instance" = "coder-v2"
      "app.kubernetes.io/name"     = "coder"
    }
  }
}

resource "helm_release" "coder-server" {

  depends_on = [ kubernetes_manifest.push ]

  name             = "coder"
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
        secretNames = [ local.ssl_vol_friendly_name ]
      }
      podAnnotations = {
        "prometheus.io/scrape" = "true"
        "prometheus.io/port"   = "2112"
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