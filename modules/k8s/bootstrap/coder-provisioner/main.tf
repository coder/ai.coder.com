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
    coderd = {
      source = "coder/coderd"
    }
  }
}

variable "cluster_name" {
  type = string
}

variable "cluster_oidc_provider_arn" {
  type = string
}

variable "role_name" {
  type    = string
  default = ""
}

variable "policy_name" {
  type    = string
  default = ""
}

variable "policy_resource_region" {
  type    = string
  default = ""
}

variable "policy_resource_account" {
  type    = string
  default = ""
}

variable "tags" {
  type    = map(string)
  default = {}
}

variable "namespace" {
  type = string
  validation {
    condition     = length(var.namespace) > 0
    error_message = "Namespace must not be empty"
  }
}

variable "image_repo" {
  type = string
}

variable "image_tag" {
  type = string
}

variable "image_pull_policy" {
  type    = string
  default = "IfNotPresent"
}

variable "image_pull_secrets" {
  type    = list(string)
  default = []
}

variable "provisioner_chart_version" {
  type    = string
  default = "2.23.0"
}

variable "logstream_chart_version" {
  type    = string
  default = "0.0.11"
}

variable "primary_access_url" {
  type = string
}

variable "ws_service_account_name" {
  type = string
}

variable "ws_service_account_labels" {
  type    = map(string)
  default = {}
}

variable "ws_service_account_annotations" {
  type    = map(string)
  default = {}
}

variable "provisioner_service_account_name" {
  type    = string
  default = "coder"
}

variable "provisioner_service_account_annotations" {
  type    = map(string)
  default = {}
}

variable "replica_count" {
  type    = number
  default = 0
}

variable "env_vars" {
  type    = map(string)
  default = {}
}

variable "resource_requests" {
  type = object({
    cpu    = string
    memory = string
  })
  default = {
    cpu    = "250m"
    memory = "512Mi"
  }
}

variable "resource_limits" {
  type = object({
    cpu    = string
    memory = string
  })
  default = {
    cpu    = "500m"
    memory = "1Gi"
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

variable "provisioner_secret" {
  type = object({
    key_secret_name                  = optional(string, "psk")
    key_secret_key                   = optional(string, "token.key")
    termination_grace_period_seconds = optional(number, 600)
  })
  default = {
    key_secret_name                  = "psk"
    key_secret_key                   = "token.key"
    termination_grace_period_seconds = 600
  }
}

variable "coder_organization_name" {
  type    = string
  default = "coder"
}

variable "coder_provisioner_key_name" {
  type    = string
  default = ""
}

##
# Coder External Provisioner 
##

data "aws_region" "this" {}

data "aws_caller_identity" "this" {}

data "coderd_organization" "this" {
  name = var.coder_organization_name
}

locals {
  region      = var.policy_resource_region == "" ? data.aws_region.this.region : var.policy_resource_region
  account_id  = var.policy_resource_account == "" ? data.aws_caller_identity.this.account_id : var.policy_resource_account
  policy_name = var.policy_name == "" ? "Provisioner-${data.aws_region.this.region}" : var.policy_name
  role_name   = var.role_name == "" ? "provisioner-${data.aws_region.this.region}" : var.role_name
}

module "provisioner-policy" {
  source      = "../../../security/policy"
  name        = local.policy_name
  path        = "/"
  description = "Coder Terraform External Provisioner Policy"
  # Use try() to handle potential data source evaluation errors
  policy_json = try(data.aws_iam_policy_document.provisioner-policy.json, "{}")
}

module "provisioner-oidc-role" {
  source       = "../../../security/role/access-entry"
  name         = local.role_name
  cluster_name = var.cluster_name
  policy_arns = {
    "AmazonEC2ReadOnlyAccess" = "arn:aws:iam::aws:policy/AmazonEC2ReadOnlyAccess"
    "TFProvisionerPolicy"     = module.provisioner-policy.policy_arn
  }
  cluster_policy_arns = {}
  oidc_principals = {
    "${var.cluster_oidc_provider_arn}" = ["system:serviceaccount:*:*"]
  }
  tags = var.tags
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
  pod_anti_affinity_preferred_during_scheduling_ignored_during_execution = [
    for v in var.pod_anti_affinity_preferred_during_scheduling_ignored_during_execution : {
      weight = v.weight
      podAffinityTerm = {
        labelSelector = v.pod_affinity_term.label_selector
        topologyKey   = v.pod_affinity_term.topology_key
      }
    }
  ]
}

module "coder-provisioner-key" {
  source          = "../../../coder/provisioner"
  organization_id = data.coderd_organization.this.id
  provisioner_tags = {
    region = data.aws_region.this.region
  }
}

resource "kubernetes_namespace" "this" {
  metadata {
    name = var.namespace
  }
}

resource "helm_release" "coder-provisioner" {
  name             = "coder-provisioner"
  namespace        = kubernetes_namespace.this.metadata[0].name
  chart            = "coder-provisioner"
  repository       = "https://helm.coder.com/v2"
  create_namespace = false
  skip_crds        = false
  wait             = true
  wait_for_jobs    = true
  version          = var.provisioner_chart_version
  timeout          = 120 # in seconds

  # Add dependency to ensure secret exists before helm install
  depends_on = [kubernetes_secret.coder-provisioner-key]

  lifecycle {
    # Prevent accidental deletion of provisioner
    prevent_destroy = false
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
      serviceAccount = {
        workspacePerms    = true
        enableDeployments = true
        name              = var.provisioner_service_account_name
        disableCreate     = false
        annotations = merge({
          "eks.amazonaws.com/role-arn" = module.provisioner-oidc-role.role_arn
        }, var.provisioner_service_account_annotations)
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
          preferredDuringSchedulingIgnoredDuringExecution = local.pod_anti_affinity_preferred_during_scheduling_ignored_during_execution
        }
      }
    }
    provisionerDaemon = {
      keySecretKey                  = var.provisioner_secret.key_secret_key
      keySecretName                 = var.provisioner_secret.key_secret_name
      terminationGracePeriodSeconds = var.provisioner_secret.termination_grace_period_seconds
    }
  })]
}

resource "kubernetes_secret" "coder-provisioner-key" {
  metadata {
    name      = var.provisioner_secret.key_secret_name
    namespace = kubernetes_namespace.this.metadata[0].name
  }
  data = {
    "${var.provisioner_secret.key_secret_key}" = module.coder-provisioner-key.provisioner_key_secret
  }
  type = "Opaque"
}

resource "helm_release" "coder-logstream" {
  name             = "coder-logstream-kube"
  namespace        = kubernetes_namespace.this.metadata[0].name
  chart            = "coder-logstream-kube"
  repository       = "https://helm.coder.com/logstream-kube"
  create_namespace = false
  skip_crds        = false
  wait             = true
  wait_for_jobs    = true
  version          = var.logstream_chart_version
  timeout          = 120 # in seconds

  # Ensure provisioner is ready before logstream
  depends_on = [helm_release.coder-provisioner]

  lifecycle {
    # Allow recreation for clean upgrades
    create_before_destroy = true
  }

  values = [yamlencode({
    url = var.primary_access_url
  })]
}

module "ws-policy" {
  source      = "../../../security/policy"
  name        = local.policy_name
  path        = "/"
  description = "Coder Workspace IAM Policy"
  policy_json = data.aws_iam_policy_document.ws-policy.json
}

module "ws-service-role" {
  source = "../../../security/role/service"
  # Dynamic name added because hardcoded names cause conflicts in multi-region deployments
  name = "ws-service-role-${data.aws_region.this.region}"
  policy_arns = {
    "AmazonEC2ContainerServiceforEC2Role" = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role",
    "AmazonSSMManagedInstanceCore"        = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",
    "WorkspacePolicy"                     = module.ws-policy.policy_arn
  }
  service_actions = ["sts:AssumeRole"]
  service_principals = [
    "ec2.amazonaws.com"
  ]
  tags = var.tags
}

module "ws-oidc-role" {
  source = "../../../security/role/access-entry"
  # Dynamic name added because hardcoded names cause conflicts in multi-region deployments
  name = "ws-container-role-${data.aws_region.this.region}"
  policy_arns = {
    "WorkspacePolicy" = module.ws-policy.policy_arn
  }
  cluster_name        = var.cluster_name
  cluster_policy_arns = {}
  oidc_principals = {
    "${var.cluster_oidc_provider_arn}" = ["system:serviceaccount:*:*"]
  }
  tags = var.tags
}

resource "kubernetes_service_account" "ws" {
  metadata {
    name      = var.ws_service_account_name
    namespace = kubernetes_namespace.this.metadata[0].name
    labels    = var.ws_service_account_labels
    annotations = merge({
      "eks.amazonaws.com/role-arn" = module.ws-oidc-role.role_arn
    }, var.ws_service_account_annotations)
  }
}

output "oidc_role_arn" {
  value = module.provisioner-oidc-role.role_arn
}