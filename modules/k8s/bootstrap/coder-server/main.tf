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
  default = null
}

variable "role_name" {
  type    = string
  default = null
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

variable "coder" {
  type = object({
    access_url = string
    wildcard_url = string
    redirect = optional(bool, true)
    image_repo = optional(string, "ghcr.io/coder/coder")
    image_tag = optional(string, "latest")
    image_pull_policy = optional(string, "IfNotPresent")
    image_pull_secrets = optional(list(string), null)
    experiments = optional(list(string), null)
    csp_policy = optional(string, null)
    env_vars = optional(map(string), {})
    rep_cnt = optional(number, 1)
    prov_rep_cnt = optional(number, 2)
    prov_force_cancel_interval = optional(string, "10m0s")
    quiet_hours = optional(string, "CRON_TZ=America/Los_Angeles 50 23 * * *")
    allow_custom_quiet = optional(bool, true)
    tf_debug_mode = optional(bool, true)
    trace_logs = optional(bool, true)
    swagger_enable = optional(bool, true)
    update_check = optional(bool, true)
    cli_upgr_msg = optional(bool, true)
    log_filter = optional(string, ".*")
  })
}

variable "prom" {
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
  type = object({
    cpu    = string
    memory = string
  })
  default = {
    cpu    = "4000m"
    memory = "8Gi"
  }
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
  type = list(object({
    key      = string
    operator = optional(string, "Equal")
    value    = string
    effect   = optional(string, "NoSchedule")
  }))
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

variable "pod_aaf_pref_sched_ie" {
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

variable "cert_config" {
  type = object({
    create_secret = bool
    name          = string
    kind          = optional(string, "ClusterIssuer")
    issuer        = optional(string, "issuer")
    store    = optional(string, "issuer")
  })
  default = {
    create_secret = true
    name          = "coder-tls"
    kind       = "ClusterIssuer"
    issuer        = "issuer"
    store        = "issuer"
  }
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
    anthropic = optional(object({
      url = string
      key = string
    }), null)
    openai = optional(object({
      url = string
      key = string
    }), null)
    bedrock = optional(object({
      url = optional(string, null)
      region = optional(string, null)
      access_id = string
      secret_id = string
      model = optional(string, "global.anthropic.claude-sonnet-4-5-20250929-v1:0")
      fast_model = optional(string, "global.anthropic.claude-haiku-4-5-20251001-v1:0")
    }), null)
  })
  default = {
    enabled = false
    anthropic = null
    openai = null
    bedrock = null
  }
}

locals {
  coder = {
    CODER_ACCESS_URL             = var.coder.access_url
    CODER_WILDCARD_ACCESS_URL    = var.coder.wildcard_url
    CODER_REDIRECT_TO_ACCESS_URL = var.coder.redirect

    CODER_ENABLE_TERRAFORM_DEBUG_MODE = var.coder.tf_debug_mode
    CODER_TRACE_LOGS                  = var.coder.trace_logs
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
    CODER_PROMETHEUS_ENABLE              = var.prom.enable
    CODER_PROMETHEUS_COLLECT_AGENT_STATS = var.prom.collect_agent_status
    CODER_PROMETHEUS_COLLECT_DB_METRICS  = var.prom.collect_db_metrics
  }
  db = {
    CODER_PG_CONNECTION_URL = "postgresql://${var.db.username}:${var.db.password}@${var.db.url}/${var.db.db}"
    CODER_PG_AUTH                = var.db.pg_auth
  }
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
  anthropic = var.aibridge.anthropic == null ? {} : {
    CODER_AIBRIDGE_ANTHROPIC_BASE_URL = var.aibridge.anthropic.url
    CODER_AIBRIDGE_ANTHROPIC_KEY = var.aibridge.anthropic.key
  }
  openai = var.aibridge.openai == null ? {} : {
    CODER_AIBRIDGE_OPENAI_BASE_URL = var.aibridge.openai.url
    CODER_AIBRIDGE_OPENAI_KEY = var.aibridge.openai.key
  }
  bedrock = var.aibridge.bedrock == null ? {} : {
    CODER_AIBRIDGE_BEDROCK_BASE_URL = var.aibridge.bedrock.url
    CODER_AIBRIDGE_BEDROCK_REGION            = var.aibridge.bedrock.region
    CODER_AIBRIDGE_BEDROCK_ACCESS_KEY        = var.aibridge.bedrock.access_id
    CODER_AIBRIDGE_BEDROCK_ACCESS_KEY_SECRET = var.aibridge.bedrock.secret_id
    CODER_AIBRIDGE_BEDROCK_MODEL = var.aibridge.bedrock.model
    CODER_AIBRIDGE_BEDROCK_SMALL_FAST_MODEL = var.aibridge.bedrock.fast_model
  }
  aibridge = merge(
    local.anthropic, 
    local.openai, 
    local.bedrock, 
    { CODER_AIBRIDGE_ENABLED = var.aibridge.enabled }
  )
  secrets = merge({
    CODER_AIBRIDGE_ANTHROPIC_KEY = try(local.anthropic["CODER_AIBRIDGE_ANTHROPIC_KEY"], null)
    CODER_AIBRIDGE_OPENAI_KEY = try(local.openai["CODER_AIBRIDGE_OPENAI_KEY"], null)
    CODER_AIBRIDGE_BEDROCK_ACCESS_KEY_SECRET = try(local.bedrock["CODER_AIBRIDGE_BEDROCK_ACCESS_KEY_SECRET"], null)
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
    local.aibridge
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

output "env" {
  value = local.env
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
  pod_aaf_pref_sched_ie = [
    for k, v in var.pod_aaf_pref_sched_ie : {
      weight = v.weight
      podAffinityTerm = {
        labelSelector = {
          matchLabels = try(v.pod_affinity_term.label_selector.match_labels, {})
        }
        topologyKey = try(v.pod_affinity_term.topology_key, {})
      }
    }
  ]
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
  region      = var.policy_resource_region == null ? data.aws_region.this.region : var.policy_resource_region
  account_id  = var.policy_resource_account == null ? data.aws_caller_identity.this.account_id : var.policy_resource_account
  policy_name = var.policy_name == null ? "coder-srv" : var.policy_name
  role_name   = var.role_name == null ? "coder-srv" : var.role_name
}

module "provisioner-policy" {

  count       = var.coder.prov_rep_cnt == 0 ? 0 : 1

  source      = "../../../security/policy"
  name        = local.policy_name
  path         = "/${var.cluster_name}/${data.aws_region.this.region}/"
  description = "Coder Terraform External Provisioner Policy"
  policy_json = data.aws_iam_policy_document.provisioner-policy.json
}

module "provisioner-oidc-role" {

  count        = var.coder.prov_rep_cnt == 0 ? 0 : 1

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

resource "kubernetes_namespace_v1" "this" {
  metadata {
    name = var.namespace
  }
}

locals {
  ssl_vol_friendly_name = replace(var.cert_config.name, ".", "-")
}

##
# Store SSL/TLS certs in Secrets Manager.
# Used to avoid throttling Let's Encrypt:
# https://letsencrypt.org/docs/rate-limits/
##

locals {
  common_name   = trimprefix(trimprefix(var.coder.access_url, "https://"), "http://")
  wildcard_name = trimprefix(trimprefix(var.coder.wildcard_url, "https://"), "http://")
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
      name = var.cert_config.name 
      namespace = kubernetes_namespace_v1.this.metadata[0].name
    }
    spec = {
      secretStoreRef = {
        kind = "ClusterSecretStore"
        name = var.cert_config.store
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
              "cert-manager.io/certificate-name" = var.cert_config.name                                                                                     
              "cert-manager.io/common-name" = local.common_name 
              "cert-manager.io/ip-sans" = ""
              "cert-manager.io/issuer-group" = ""                                                                                                                   
              "cert-manager.io/issuer-kind" = "ClusterIssuer"                                                                                               
              "cert-manager.io/issuer-name" = var.cert_config.issuer
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
      name = var.cert_config.name
      namespace = kubernetes_namespace_v1.this.metadata[0].name
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
        kind = var.cert_config.kind
        name = var.cert_config.issuer
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
      name = var.cert_config.name 
      namespace = kubernetes_namespace_v1.this.metadata[0].name
    }
    spec = {
      updatePolicy = "Replace"
      deletionPolicy = "None"
      refreshInterval = local.secret_refresh_interval
      secretStoreRefs = [{
        kind = "ClusterSecretStore"
        name = var.cert_config.store
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

resource "kubernetes_service_v1" "prometheus" {
  metadata {
    name      = "coder-prometheus"
    namespace = kubernetes_namespace_v1.this.metadata[0].name
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
  namespace        = kubernetes_namespace_v1.this.metadata[0].name
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
        repo        = var.coder.image_repo
        tag         = var.coder.image_tag
        pullPolicy  = var.coder.image_pull_policy
        pullSecrets = var.coder.image_pull_secrets
      }
      env = local.env
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
        loadBalancerClass     = var.lb_class
        annotations           = var.svc_annot
      }
      replicaCount = var.coder.rep_cnt
      resources = {
        requests = var.resource_request
        limits   = var.resource_limit
      }
      serviceAccount = {
        annotations = var.coder.prov_rep_cnt == 0 ? var.svc_acc_annot : merge({
          "eks.amazonaws.com/role-arn" : module.provisioner-oidc-role[0].role_arn
        }, var.svc_acc_annot)
      }
      nodeSelector              = var.node_selector
      tolerations               = var.tolerations
      topologySpreadConstraints = local.topology_spread
      affinity = {
        podAntiAffinity = {
          preferredDuringSchedulingIgnoredDuringExecution = local.pod_aaf_pref_sched_ie
        }
      }
      terminationGracePeriodSeconds = var.termination_grace_period
    }
  })]
}

output "namespace" {
  value = kubernetes_namespace_v1.this.metadata[0].name
}