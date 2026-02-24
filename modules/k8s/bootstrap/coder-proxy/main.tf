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
    coderd = {
      source = "coder/coderd"
    }
    tls = {
      source = "hashicorp/tls"
    }
  }
}

##
# Coderd Inputs
##

variable "proxy" {
  type = object({
    access_url = string
    wildcard_url = string
    coder_access_url = string
    mount_ssl = optional(bool, false)
    mount_ssl_name = optional(string, "cert")
    name = string
    display_name = string
    icon = optional(string, "")
    rep_cnt = optional(number, 1)
    image_repo = optional(string, "ghcr.io/coder/coder")
    image_tag = optional(string, "latest")
    image_pull_policy = optional(string, "IfNotPresent")
    image_pull_secrets = optional(list(string), null)
    trace_logs = optional(bool, true)
    log_filter = optional(string, ".*")
  })
}

##
# Kubernetes Inputs
##

variable "release_name" {
  description = "The release name of the installed Helm app."
  type = string
  default = "coder-proxy"
}

variable "chart_name" {
  description = "The chart name of the installed Helm app."
  type = string
  default = "coder"
}

variable "namespace" {
  type = string
}

variable "chart_timeout" {
  type    = number
  default = 300 # In Seconds
}

variable "chart_version" {
  type    = string
  default = "2.30.0"
}

variable "env_vars" {
  type    = map(string)
  default = {}
}

variable "lb_class" {
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
  type = map(string)
  default = {}
}

variable "svc_annot" {
  type    = map(string)
  default = {}
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

variable "termination_grace_period" {
  type    = number
  default = 600
}

resource "coderd_workspace_proxy" "this" {
  name         = var.proxy.name
  display_name = var.proxy.display_name
  icon         = var.proxy.icon
}

locals {
  proxy = {
    CODER_ACCESS_URL          = var.proxy.access_url
    CODER_WILDCARD_ACCESS_URL = var.proxy.wildcard_url
    CODER_PRIMARY_ACCESS_URL  = var.proxy.coder_access_url
    CODER_PROXY_SESSION_TOKEN = coderd_workspace_proxy.this.session_token
    CODER_TRACE_LOGS                  = var.proxy.trace_logs
    CODER_LOG_FILTER                  = var.proxy.log_filter
  }
  secrets = {
    CODER_PROXY_SESSION_TOKEN = local.proxy["CODER_PROXY_SESSION_TOKEN"]
  }
  secret_key = "key"
  secret_keys = keys(local.secrets)
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
  env = concat([ for k,v in merge(
    local.proxy
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

resource "kubernetes_namespace_v1" "this" {
  metadata {
    name = var.namespace
  }
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
      target_port = var.proxy.mount_ssl ? "https" : "http"
    }
    selector = {
      "app.kubernetes.io/instance" = var.release_name
      "app.kubernetes.io/name"     = var.chart_name
      "app.kubernetes.io/part-of" = var.chart_name
    }
  }
}

resource "helm_release" "coder-proxy" {
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
  timeout          = var.chart_timeout

  values = [yamlencode({
    coder = {
      image = {
        repo        = var.proxy.image_repo
        tag         = var.proxy.image_tag
        pullPolicy  = var.proxy.image_pull_policy
        pullSecrets = var.proxy.image_pull_secrets
      }
      workspaceProxy = true
      env            = local.env
      service = {
        enable                = false
      }
      tls = {
        secretNames = var.proxy.mount_ssl ? [ var.proxy.mount_ssl_name ] : []
      }
      replicaCount = var.proxy.rep_cnt
      resources = {
        requests = var.resource_request
        limits   = var.resource_limit
      }
      serviceAccount = {
        annotations = var.svc_acc_annot
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