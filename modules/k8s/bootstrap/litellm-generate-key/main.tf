terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
      # Added version constraint for reproducibility and maintainability
      version = ">= 5.0"
    }
    kubernetes = {
      source = "hashicorp/kubernetes"
      # Added version constraint for reproducibility and maintainability
      version = ">= 2.20"
    }
  }
}

variable "cluster_name" {
  type = string
  validation {
    condition     = length(var.cluster_name) > 0
    error_message = "Cluster name must not be empty"
  }
}

variable "cluster_oidc_provider_arn" {
  type = string
  validation {
    condition     = can(regex("^arn:aws:iam::", var.cluster_oidc_provider_arn))
    error_message = "Cluster OIDC provider ARN must be a valid IAM ARN"
  }
}

variable "role_name" {
  type    = string
  default = ""
}

variable "policy_name" {
  type    = string
  default = ""
}

variable "namespace" {
  type    = string
  default = "litellm"
}

variable "name" {
  type    = string
  default = "rotate-key"
}

variable "image_repo" {
  type = string
  validation {
    condition     = length(var.image_repo) > 0
    error_message = "Image repository must not be empty"
  }
}

variable "image_tag" {
  type = string
  validation {
    condition     = length(var.image_tag) > 0
    error_message = "Image tag must not be empty"
  }
}

variable "rotate_key_script_file_name" {
  type    = string
  default = "rotate.sh"
}

variable "litellm_key_secret_name" {
  type    = string
  default = "litellm.env"
}

variable "litellm_key_master_secret_key" {
  type    = string
  default = "master"
}

variable "litellm_key_salt_secret_key" {
  type    = string
  default = "salt"
}

variable "litellm_master_key" {
  type      = string
  sensitive = true
  default   = ""
}

variable "litellm_salt_key" {
  type      = string
  sensitive = true
  default   = ""
}

variable "litellm_create_secret" {
  type    = bool
  default = false
}

variable "litellm_url" {
  type = string
  validation {
    condition     = can(regex("^https?://", var.litellm_url))
    error_message = "LiteLLM URL must start with http:// or https://"
  }
}

variable "tags" {
  type    = map(string)
  default = {}
}

variable "secret_id" {
  type      = string
  sensitive = true
  validation {
    condition     = length(var.secret_id) > 0
    error_message = "Secret ID must not be empty"
  }
}

variable "secret_region" {
  type      = string
  sensitive = true
  validation {
    condition     = length(var.secret_region) > 0
    error_message = "Secret region must not be empty"
  }
}

data "aws_region" "this" {}

data "aws_caller_identity" "this" {}

locals {
  app_labels = {
    "app.kubernetes.io/name" : var.name
    "app.kubernetes.io/part-of" : var.name
  }
  policy_name = var.policy_name == "" ? "LiteLLM-Create-${data.aws_region.this.region}" : var.policy_name
  role_name   = var.role_name == "" ? "litellm-create-${data.aws_region.this.region}" : var.role_name
}

# Create custom policy for least privilege access
data "aws_iam_policy_document" "litellm_secrets" {
  statement {
    sid    = "SecretsManagerAccess"
    effect = "Allow"
    # Restrict to specific secret operations for least privilege
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:PutSecretValue",
      "secretsmanager:UpdateSecret"
    ]
    resources = ["arn:aws:secretsmanager:${var.secret_region}:${data.aws_caller_identity.this.account_id}:secret:${var.secret_id}*"]
  }
}

resource "aws_iam_policy" "litellm_secrets" {
  name        = "${local.policy_name}-secrets"
  description = "LiteLLM secrets access policy"
  policy      = data.aws_iam_policy_document.litellm_secrets.json
}

module "oidc-role" {
  source       = "../../../security/role/access-entry"
  name         = local.role_name
  cluster_name = var.cluster_name
  policy_arns = {
    "LiteLLMSecretsPolicy" = aws_iam_policy.litellm_secrets.arn
  }
  # Removed overly broad EKS cluster admin policy for least privilege
  cluster_policy_arns = {}
  oidc_principals = {
    "${var.cluster_oidc_provider_arn}" = ["system:serviceaccount:${var.namespace}:${var.name}"]
  }
  tags = var.tags
}

resource "kubernetes_role" "this" {
  metadata {
    name      = var.name
    namespace = var.namespace
    labels    = local.app_labels
  }
  rule {
    api_groups     = [""]
    resources      = ["secrets"]
    resource_names = [var.litellm_key_secret_name]
    verbs          = ["get", "create", "update", "patch"]
  }
  rule {
    api_groups     = ["apps", "extensions"]
    resources      = ["deployments"]
    resource_names = [var.name]
    verbs          = ["get", "patch"]
  }
}

resource "kubernetes_service_account" "this" {
  metadata {
    name      = var.name
    namespace = var.namespace
    annotations = {
      "eks.amazonaws.com/role-arn" : module.oidc-role.role_arn
    }
    labels = local.app_labels
  }
}

resource "kubernetes_role_binding" "this" {
  metadata {
    name      = var.name
    namespace = var.namespace
    labels    = local.app_labels
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role.this.metadata[0].name
  }
  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.this.metadata[0].name
    namespace = var.namespace
  }
}

resource "kubernetes_config_map" "this" {
  metadata {
    name      = var.name
    namespace = var.namespace
    labels    = local.app_labels
  }
  data = {
    "${var.rotate_key_script_file_name}" = templatefile("${path.module}/scripts/${var.rotate_key_script_file_name}", {})
  }
}

locals {
  primary_env_vars = {
    LITELLM_URL            = var.litellm_url
    AWS_SECRETS_MANAGER_ID = var.secret_id
    AWS_SECRET_REGION      = var.secret_region
    KEY_NAME               = "litellm-tmp"
    KEY_DURATION           = "8h"
    USERNAME               = "robot_user.ai"
    USER_EMAIL             = "robot_user@gmail.com"
  }
  secret_env_vars = {
    LITELLM_MASTER_KEY = {
      name = var.litellm_key_secret_name
      key  = var.litellm_key_master_secret_key
    }
    LITELLM_SALT_KEY = {
      name = var.litellm_key_secret_name
      key  = var.litellm_key_salt_secret_key
    }
  }
}

resource "kubernetes_secret" "key" {
  count = var.litellm_create_secret ? 1 : 0
  metadata {
    name      = var.litellm_key_secret_name
    namespace = var.namespace
    labels    = local.app_labels
  }
  data = {
    "${var.litellm_key_master_secret_key}" = var.litellm_master_key
    "${var.litellm_key_salt_secret_key}"   = var.litellm_salt_key
  }
}


resource "kubernetes_cron_job_v1" "this" {
  metadata {
    name      = var.name
    namespace = var.namespace
    labels    = local.app_labels
  }
  spec {
    timezone                      = "America/Vancouver"
    successful_jobs_history_limit = 0
    failed_jobs_history_limit     = 1
    concurrency_policy            = "Replace"
    schedule                      = "*/5 * * * *"
    job_template {
      metadata {
        labels = local.app_labels
      }
      spec {
        parallelism = 1
        template {
          metadata {
            labels = local.app_labels
          }
          spec {
            service_account_name = kubernetes_service_account.this.metadata[0].name
            restart_policy       = "OnFailure"
            container {
              name              = var.name
              image             = "${var.image_repo}:${var.image_tag}"
              image_pull_policy = "IfNotPresent"
              command           = split(" ", "/bin/bash -c /tmp/${var.rotate_key_script_file_name}")
              dynamic "env" {
                for_each = local.primary_env_vars
                content {
                  name  = env.key
                  value = tostring(env.value)
                }
              }
              dynamic "env" {
                for_each = local.secret_env_vars
                content {
                  name = env.key
                  value_from {
                    secret_key_ref {
                      name = env.value.name
                      key  = env.value.key
                    }
                  }
                }
              }
              volume_mount {
                name       = kubernetes_config_map.this.metadata[0].name
                mount_path = "/tmp/${var.rotate_key_script_file_name}"
                sub_path   = var.rotate_key_script_file_name
              }
            }
            volume {
              name = kubernetes_config_map.this.metadata[0].name
              config_map {
                name = kubernetes_config_map.this.metadata[0].name
                # Changed to 0555 because 0777 is overly permissive, script should be read-only and executable
                default_mode = "0555"
              }
            }
          }
        }
      }
    }
  }
}