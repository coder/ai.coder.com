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
  }
}

variable "chart_name" {
  type = string
  default = "coder-provisioner"
}

variable "chart_version" {
  type    = string
  default = "2.30.0"
}

variable "chart_timeout" {
  type    = number
  default = 300
}

variable "release_name" {
  type    = string
  default = "coder-provisioner"
}

variable "cluster_name" {
  type = string
}

variable "cluster_oidc_provider_arn" {
  type = string
}

variable "tags" {
  type    = map(string)
  default = {}
}

variable "coder" {
  type = object({
    access_url = string
    prov_tags = optional(map(string), {})
    prov_secret_key = optional(string, "key")
    org_name = optional(string, "coder")
    ws_ns = optional(list(string), [])
    image_repo = optional(string, "ghcr.io/coder/coder")
    image_tag = optional(string, "latest")
    image_pull_policy = optional(string, "IfNotPresent")
    image_pull_secrets = optional(list(string), null)
    env_vars = optional(map(string), {})
    rep_cnt = optional(number, 1)
    tf_debug_mode = optional(bool, true)
    trace_logs = optional(bool, true)
  })
  # sensitive = true
}

variable "namespace" {
  type = string
  default = "coder-provisioner"
}

variable "svc_acc" {
  type = object({
    create = optional(bool, true)
    name = optional(string, "coder-provisioner")
    annots = optional(map(string), {})
  })
  default = {
    create = true
    name = "coder-provisioner"
    annots = {}
  }
}

variable "rsrc_req" {
  type = object({
    cpu    = string
    memory = string
  })
  default = {
    cpu    = "250m"
    memory = "512Mi"
  }
}

variable "rsrc_lim" {
  type = object({
    cpu    = string
    memory = string
  })
  default = {
    cpu    = "1000m"
    memory = "2Gi"
  }
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

##
# Coder External Provisioner 
##

data "aws_region" "this" {}
data "aws_caller_identity" "this" {}

data "coderd_organization" "this" {
  name = var.coder.org_name
}

locals {
  region      = data.aws_region.this.region
  account_id  = data.aws_caller_identity.this.account_id
  policy_name = "Provisioner-${data.aws_region.this.region}"
  role_name   = "provisioner-${data.aws_region.this.region}"
}

module "iam-policy" {
  source      = "../../../security/policy"
  name        = local.policy_name
  path        = "/"
  description = "Coder External Provisioner Policy"
  policy_json = data.aws_iam_policy_document.ext-prov.json
}

module "oidc-role" {
  source       = "../../../security/role/access-entry"
  name         = local.role_name
  cluster_name = var.cluster_name
  policy_arns = {
    "AmazonEC2ReadOnlyAccess" = "arn:aws:iam::aws:policy/AmazonEC2ReadOnlyAccess"
    "TFProvisionerPolicy"     = module.iam-policy.policy_arn
  }
  cluster_policy_arns = {}
  oidc_principals = {
    "${var.cluster_oidc_provider_arn}" = ["system:serviceaccount:*:*"]
  }
  tags = var.tags
}

module "ext-prov" {
  source          = "../../../coder/provisioner"
  organization_id = data.coderd_organization.this.id
  provisioner_tags = var.coder.prov_tags
}

resource "kubernetes_namespace_v1" "this" {
  metadata {
    name = var.namespace
  }
}

resource "kubernetes_secret_v1" "ext-prov" {
  metadata {
    name      = module.ext-prov.provisioner_key_name
    namespace = kubernetes_namespace_v1.this.metadata[0].name
    annotations = {
      "custom.kubernetes.secret/key" = var.coder.prov_secret_key
    }
  }
  type = "Opaque"
  data = {
    "${var.coder.prov_secret_key}" = module.ext-prov.provisioner_key_secret
  }
}

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

resource "helm_release" "coder-provisioner" {
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
        repo        = var.coder.image_repo
        tag         = var.coder.image_tag
        pullPolicy  = var.coder.image_pull_policy
        pullSecrets = var.coder.image_pull_secrets
      }
      serviceAccount = {
        workspacePerms    = true
        enableDeployments = true
        name              = var.svc_acc.name
        disableCreate     = !var.svc_acc.create
        workspaceNamespaces = [ for v in var.coder.ws_ns : { name = v  } ]
        annotations = merge({
          "eks.amazonaws.com/role-arn" = module.oidc-role.role_arn
        }, var.svc_acc.annots)
      }
      podAnnotations = {
        "prometheus.io/scrape" = "true"
        "prometheus.io/port"   = "2112"
      }
      env = [
        for k, v in merge({
          CODER_URL = var.coder.access_url
        }, var.coder.env_vars) : { name = k, value = v }
      ]
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
        requests = var.rsrc_req
        limits   = var.rsrc_lim
      }
      nodeSelector              = var.node_selector
      replicaCount              = var.coder.rep_cnt
      tolerations               = var.tolerations
      topologySpreadConstraints = local.topology_spread
      affinity = {
        podAntiAffinity = {
          preferredDuringSchedulingIgnoredDuringExecution = local.pod_aaf_pref_sched_ie
        }
      }
    }
    provisionerDaemon = {
      keySecretKey                  = kubernetes_secret_v1.ext-prov.metadata[0].annotations["custom.kubernetes.secret/key"]
      keySecretName                 = kubernetes_secret_v1.ext-prov.metadata[0].name
      terminationGracePeriodSeconds = 600
    }
  })]
}

output "coderd_organization_id" {

  depends_on = [ helm_release.coder-provisioner ]
  
  value = data.coderd_organization.this.id
}

output "k8s_namespace" {

  depends_on = [ helm_release.coder-provisioner ]
  
  value = kubernetes_namespace_v1.this.metadata[0].name
}