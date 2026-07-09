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
  }
}

variable "release_name" {
  description = "The release name of the installed Helm app."
  type = string
  default = "coder"
}

variable "chart_name" {
  description = "The chart name of the installed Helm app."
  type = string
  default = "coder"
}

variable "cluster_name" {
  type = string
}

variable "cluster_oidc_provider_arn" {
  type = string
}

variable "policy_resource_region" {
  type    = string
  default = null
}

variable "policy_resource_account" {
  type    = string
  default = null
}

variable "policy_name" {
  type    = string
  default = "coder-srv"
}

variable "role_name" {
  type    = string
  default = "coder-srv"
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

variable "chart_version" {
  type    = string
  default = "2.25.1"
}

variable "coder" {
  type = object({
    access_url = string
    wildcard_url = string
    redirect = optional(bool, true)
    mount_ssl = optional(bool, false)
    mount_ssl_name = optional(string, "cert")
    image_repo = optional(string, "ghcr.io/coder/coder")
    image_tag = optional(string, "latest")
    image_pull_policy = optional(string, "IfNotPresent")
    image_pull_secrets = optional(list(string), null)
    csp_policy = optional(string, null)
    env_vars = optional(map(string), {})
    rep_cnt = optional(number, 1)
    prov_rep_cnt = optional(number, 2)
    prov_force_cancel_interval = optional(string, "10m0s")
    quiet_hours = optional(string, "CRON_TZ=America/Los_Angeles 50 23 * * *")
    allow_custom_quiet = optional(bool, true)
    tf_debug_mode = optional(bool, true)
    trace_logs = optional(bool, true)
    enable_tracing = optional(bool, true)
    swagger_enable = optional(bool, true)
    update_check = optional(bool, true)
    cli_upgr_msg = optional(bool, true)
    log_filter = optional(string, ".*")
  })
}

variable "prometheus" {
  type = object({
    enable = optional(bool, true)
    collect_agent_status = optional(bool, true)
    collect_db_metrics = optional(bool, true)
  })
  default = {
    enable = false
    collect_agent_status = false
    collect_db_metrics = false
  }
}

variable "termination_grace_period" {
  type = number
  default = 600
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

variable "tags" {
  type = map(string)
  default = {}
}

variable "resource_limit" {
  type = map(any)
  default = {}
}

variable "svc_annot" {
  type    = map(string)
  default = {}
}

variable "lb_class" {
  type = string
  default = "service.k8s.aws/nlb"
}

variable "svc_acc_annot" {
  type    = map(string)
  default = {}
}

variable "node_selector" {
  type    = map(string)
  default = {}
}

variable "tolerations" {
  type = list(any)
  default = []
}

variable "topology_spread" {
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

variable "affinity" {
  type = any
  default = {}
}

variable "db" {
  type = object({
    url = string
    username = string
    password = string
    db = optional(string, "coder")
    pg_auth = optional(string, "password")
  })
}

variable "oidc" {
  type = object({
    enable = bool
    sign_in_text = string
    icon_url     = string
    scopes       = optional(list(string), null)
    email_domain = string
    issuer_url = optional(string, null)
    client_id = optional(string, null)
    client_secret = optional(string, null)
  })
  default = {
    enable = false
    sign_in_text = null
    icon_url     = null
    scopes       = null
    email_domain = null
    issuer_url   = null
    client_id = null
    client_secret = null
  }
}

variable "oauth2" {
  type = object({
    enable = bool
    default_provider_enable = bool
    allow_signups = bool
    device_flow = bool
    allowed_orgs = list(string) # Empty list means allow everyone
    client_id = string
    client_secret = string
    use_extern_auth = bool
  })
  default = {
    enable = false
    default_provider_enable = false
    allow_signups = true
    device_flow = false
    allowed_orgs = []
    client_id = null
    client_secret = null
    use_extern_auth = false
  }
}

variable "extern_auth" {
  type = list(object({
    id = string
    type = string
    client_id = string
    client_secret = string
    auth_url = optional(string, null)
    token_url = optional(string, null)
    revoke_url = optional(string, null)
    validate_url = optional(string, null)
    regex = optional(string, null)
  }))
  default = []
}

variable "aibridge" {
  type = object({
    enabled = bool
    enable_structured_logging = optional(bool, true)
  })
  default = {
    enabled = false
    enable_structured_logging = true
  }
}

locals {
  coder = {
    CODER_ACCESS_URL             = var.coder.access_url
    CODER_WILDCARD_ACCESS_URL    = var.coder.wildcard_url

    # TLS Termination handled on the LB
    CODER_REDIRECT_TO_ACCESS_URL = var.coder.mount_ssl
    CODER_TLS_ENABLE = var.coder.mount_ssl

    CODER_ENABLE_TERRAFORM_DEBUG_MODE = var.coder.tf_debug_mode
    CODER_TRACE_LOGS                  = var.coder.trace_logs
    CODER_TRACE_ENABLE                = var.coder.enable_tracing
    CODER_LOG_FILTER                  = var.coder.log_filter
    CODER_SWAGGER_ENABLE              = var.coder.swagger_enable
    CODER_UPDATE_CHECK                = var.coder.update_check
    CODER_CLI_UPGRADE_MESSAGE         = var.coder.cli_upgr_msg

    CODER_PROVISIONER_DAEMONS               = var.coder.prov_rep_cnt
    CODER_PROVISIONER_FORCE_CANCEL_INTERVAL = var.coder.prov_force_cancel_interval
    CODER_QUIET_HOURS_DEFAULT_SCHEDULE      = var.coder.quiet_hours
    CODER_ALLOW_CUSTOM_QUIET_HOURS          = var.coder.allow_custom_quiet
  }
  prom = {
    CODER_PROMETHEUS_ENABLE              = var.prometheus.enable
    CODER_PROMETHEUS_COLLECT_AGENT_STATS = var.prometheus.collect_agent_status
    CODER_PROMETHEUS_COLLECT_DB_METRICS  = var.prometheus.collect_db_metrics
  }
  db = merge({
    CODER_PG_AUTH                = var.db.pg_auth
  }, var.db.pg_auth == "awsiamrds" ? {
    CODER_PG_CONNECTION_URL = "postgresql://${var.db.username}@${var.db.url}/${var.db.db}"
  } : {
    CODER_PG_CONNECTION_URL = "postgresql://${var.db.username}:${var.db.password}@${var.db.url}/${var.db.db}"
  })
  oidc = !var.oidc.enable ? {} : {
    CODER_OIDC_ISSUER_URL = var.oidc.issuer_url
    CODER_OIDC_CLIENT_ID = var.oidc.client_id
    CODER_OIDC_CLIENT_SECRET = var.oidc.client_secret
    CODER_OIDC_SIGN_IN_TEXT = var.oidc.sign_in_text
    CODER_OIDC_ICON_URL     = var.oidc.icon_url
    CODER_OIDC_SCOPES       = join(",", var.oidc.scopes)
    CODER_OIDC_EMAIL_DOMAIN = var.oidc.email_domain
  }
  oauth2 = !var.oauth2.enable ? {
    CODER_OAUTH2_GITHUB_DEFAULT_PROVIDER_ENABLE = false
  } : {
    CODER_OAUTH2_GITHUB_DEFAULT_PROVIDER_ENABLE = var.oauth2.default_provider_enable
    CODER_OAUTH2_GITHUB_CLIENT_ID = var.oauth2.client_id
    CODER_OAUTH2_GITHUB_CLIENT_SECRET = var.oauth2.client_secret
    CODER_OAUTH2_GITHUB_ALLOW_SIGNUPS = var.oauth2.allow_signups
    CODER_OAUTH2_GITHUB_DEVICE_FLOW = var.oauth2.device_flow
    CODER_OAUTH2_GITHUB_ALLOW_EVERYONE = "${length(var.oauth2.allowed_orgs) == 0}"
    CODER_OAUTH2_GITHUB_ALLOWED_ORGS = join(",", var.oauth2.allowed_orgs)
  }
  extern_auth = merge([for index, obj in var.extern_auth : {
    "CODER_EXTERNAL_AUTH_${index}_ID" = obj.id
    "CODER_EXTERNAL_AUTH_${index}_TYPE" = obj.type
    "CODER_EXTERNAL_AUTH_${index}_CLIENT_ID" = obj.client_id
    "CODER_EXTERNAL_AUTH_${index}_CLIENT_SECRET" = obj.client_secret
    "CODER_EXTERNAL_AUTH_${index}_AUTH_URL" = obj.auth_url
    "CODER_EXTERNAL_AUTH_${index}_TOKEN_URL" = obj.token_url
    "CODER_EXTERNAL_AUTH_${index}_REVOKE_URL" = obj.revoke_url
    "CODER_EXTERNAL_AUTH_${index}_VALIDATE_URL" = obj.validate_url
    "CODER_EXTERNAL_AUTH_${index}_REGEX" = obj.regex
  }]...)
  aibridge = merge(
    { 
      CODER_AIBRIDGE_ENABLED = var.aibridge.enabled 
      CODER_AIBRIDGE_STRUCTURED_LOGGING = var.aibridge.enable_structured_logging
    }
  )
  secrets = merge({
    CODER_OAUTH2_GITHUB_CLIENT_SECRET = try(local.oauth2["CODER_OAUTH2_GITHUB_CLIENT_SECRET"], null)
    CODER_OIDC_CLIENT_SECRET = try(local.oidc["CODER_OIDC_CLIENT_SECRET"], null)
    CODER_PG_CONNECTION_URL = try(local.db["CODER_PG_CONNECTION_URL"], null)
  }, { for index, obj in var.extern_auth : 
    "CODER_EXTERNAL_AUTH_${index}_CLIENT_SECRET" => obj.client_secret 
  })
  secret_key = "key"
  secret_keys = keys(local.secrets)
  env = concat([ for k,v in merge(
    local.coder,
    local.prom, 
    local.db,
    local.oidc,
    local.oauth2,
    local.extern_auth,
    local.aibridge,
    var.coder.env_vars
  ) : { 
    name = k, 
    value = tostring(v)
  } if lookup(local.secrets, k, null) == null ], [
    for k,v in local.secrets : { 
      name = k, 
      valueFrom = { 
        secretKeyRef = { 
          name = replace(lower(k), "_", "-"), 
          key = local.secret_key
        } 
      } 
    } if v != null
  ])
}

resource "kubernetes_secret_v1" "coder" {

  for_each = toset(local.secret_keys)

  metadata {
    name = replace(lower(each.key), "_", "-")
    namespace = kubernetes_namespace_v1.this.metadata[0].name
    annotations = {
      "custom.kubernetes.secret/key" = local.secret_key
    }
  }
  data = {
    "${local.secret_key}" = sensitive(local.secrets[each.key])
  }
}

data "aws_region" "this" {}

data "aws_caller_identity" "this" {}

locals {
  topology_spread = [
    for k, v in var.topology_spread : {
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
  region      = data.aws_region.this.region
  account_id  = data.aws_caller_identity.this.account_id
}

module "provisioner-policy" {

  count       = var.coder.prov_rep_cnt == 0 ? 0 : 1

  source      = "../../../security/policy"
  name        = var.policy_name
  path         = "/${var.cluster_name}/${local.region}/"
  description = "Coder Terraform External Provisioner Policy"
  policy_json = data.aws_iam_policy_document.provisioner.json
}

module "rds-policy" {
  source      = "../../../security/policy"
  name        = "${var.policy_name}-${local.rds_db_name}"
  path         = "/${var.cluster_name}/${local.region}/"
  description = "Coder DB IAM Access Policy"
  policy_json = data.aws_iam_policy_document.rds.json
}

module "provisioner-oidc-role" {
  source       = "../../../security/role/access-entry"
  name         = var.role_name
  path         = "/${var.cluster_name}/${local.region}/"
  cluster_name = var.cluster_name
  policy_arns = merge({
    "AmazonEC2ReadOnlyAccess" = "arn:aws:iam::aws:policy/AmazonEC2ReadOnlyAccess"
    "CoderRDSDBPolicy" = module.rds-policy.policy_arn
  }, var.coder.prov_rep_cnt == 0 ? {} : {
    "TFProvisionerPolicy"     = module.provisioner-policy[0].policy_arn
  })
  cluster_policy_arns = {}
  oidc_principals = {
    "${var.cluster_oidc_provider_arn}" = ["system:serviceaccount:*:*"]
  }
  tags = var.tags
}

resource "kubernetes_namespace_v1" "this" {
  metadata {
    name = var.namespace
  }
}

resource "kubernetes_service_v1" "coder" {
  
  wait_for_load_balancer = true

  metadata {
    name      = var.release_name
    namespace = kubernetes_namespace_v1.this.metadata[0].name
    labels = {}
    annotations = var.svc_annot
  }
  spec {
    type = "LoadBalancer"
    load_balancer_class = var.lb_class
    port {
      name = "http"
      port = 80
      protocol = "TCP"
      target_port = "http"
    }
    port {
      name = "https"
      port = 443
      protocol = "TCP"
      target_port = var.coder.mount_ssl ? "https" : "http"
    }
    selector = {
      "app.kubernetes.io/instance" = var.chart_name
      "app.kubernetes.io/name"     = var.release_name
    }
  }
}

resource "kubernetes_service_v1" "prometheus" {
  count = var.prometheus.enable ? 1 : 0
  metadata {
    name      = "${var.release_name}-prometheus"
    namespace = kubernetes_namespace_v1.this.metadata[0].name
    labels = {}
  }
  spec {
    type       = "ClusterIP"
    cluster_ip = "None"
    port {
      name        = "http"
      protocol    = "TCP"
      port        = 2112
      target_port = 2112
    }
    selector = {
      "app.kubernetes.io/instance" = var.chart_name
      "app.kubernetes.io/name"     = var.release_name
    }
  }
}

resource "helm_release" "coder-server" {

  name             = var.release_name
  namespace        = kubernetes_namespace_v1.this.metadata[0].name
  chart            = var.chart_name
  repository       = "https://helm.coder.com/v2"
  create_namespace = false
  upgrade_install  = true
  skip_crds        = false
  wait             = true
  wait_for_jobs    = true
  version          = var.chart_version
  timeout          = var.helm_timeout

  values = [yamlencode({
    coder = {
      image = {
        repo        = var.coder.image_repo
        tag         = var.coder.image_tag
        pullPolicy  = var.coder.image_pull_policy
        pullSecrets = var.coder.image_pull_secrets
      }
      env = local.env
      annotations = var.prometheus.enable ? {
        "prometheus.io/scrape" = "true"
        "prometheus.io/port"   = kubernetes_service_v1.prometheus[0].spec[0].port[0].port
      } : {}
      podAnnotations = var.prometheus.enable ? {
        "prometheus.io/scrape" = "true"
        "prometheus.io/port"   = kubernetes_service_v1.prometheus[0].spec[0].port[0].port
      } : {}
      service = {
        enable                = false
      }
      tls = {
        secretNames = var.coder.mount_ssl ? [ var.coder.mount_ssl_name ] : []
      }
      replicaCount = var.coder.rep_cnt
      resources = {
        requests = var.resource_request
        limits   = var.resource_limit
      }
      serviceAccount = {
        annotations = merge({
          "eks.amazonaws.com/role-arn" : module.provisioner-oidc-role.role_arn
        }, var.svc_acc_annot)
      }
      nodeSelector              = var.node_selector
      tolerations               = var.tolerations
      topologySpreadConstraints = local.topology_spread
      affinity = var.affinity
      terminationGracePeriodSeconds = var.termination_grace_period
    }
  })]
}

output "namespace" {
  value = kubernetes_namespace_v1.this.metadata[0].name
}