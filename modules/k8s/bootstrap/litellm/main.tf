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
  # Optional override for policy resource region, defaults to current region if empty
  type    = string
  default = ""
}

variable "policy_resource_account" {
  # Optional override for policy resource account, defaults to current account if empty
  type    = string
  default = ""
}

variable "namespace" {
  type    = string
  default = "litellm"
}

variable "name" {
  type    = string
  default = "litellm"
}

variable "replicas" {
  type    = number
  default = 0
}

variable "image_repo" {
  type    = string
  default = "ghcr.io/berriai/litellm"
}

variable "image_tag" {
  type    = string
  default = "v1.72.6-stable"
}

variable "app_container_port" {
  type    = number
  default = 4000
}

variable "host_name" {
  type = string
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

variable "aws_ingress_certificate_arn" {
  type      = string
  sensitive = true
}

variable "aws_bedrock_region" {
  type    = string
  default = "us-east-2"
}

variable "db_url_secret_name" {
  type    = string
  default = "url"
}

variable "db_url_secret_key" {
  type    = string
  default = "postgres.env"
}

variable "db_url" {
  type      = string
  sensitive = true
}

variable "redis_host_secret_name" {
  type    = string
  default = "redis.env"
}

variable "redis_host_secret_key" {
  type    = string
  default = "host"
}

variable "redis_password_secret_key" {
  type    = string
  default = "password"
}

variable "redis_host" {
  type      = string
  sensitive = true
}

variable "redis_password" {
  type      = string
  sensitive = true
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

variable "litellm_salt_key" {
  type      = string
  sensitive = true
}

variable "litellm_master_key" {
  type      = string
  sensitive = true
}

variable "gcloud_auth_secret_name" {
  type    = string
  default = "gcloud-auth"
}

variable "gcloud_auth_secret_key" {
  type    = string
  default = "service_account.json"
}

variable "gcloud_auth_file_path" {
  type    = string
  default = "/tmp"
}

variable "gcloud_auth" {
  type      = string
  sensitive = true
}

variable "litellm_config_name" {
  type    = string
  default = "config-yaml"
}

variable "litellm_config_key" {
  type    = string
  default = "config.yaml"
}

variable "litellm_config_middleware_name" {
  type    = string
  default = "strip-header-middleware-py"
}

variable "litellm_config_middleware_key" {
  type    = string
  default = "strip_header_middleware.py"
}

variable "tags" {
  type    = map(string)
  default = {}
}

data "aws_region" "this" {}

data "aws_caller_identity" "this" {}

locals {
  app_labels = {
    "app.kubernetes.io/name" : var.name
    "app.kubernetes.io/part-of" : var.name
  }
}

resource "kubernetes_namespace" "this" {
  metadata {
    name = var.namespace
  }
}

resource "kubernetes_ingress_v1" "this" {
  metadata {
    name      = var.name
    namespace = kubernetes_namespace.this.metadata[0].name
    annotations = {
      "alb.ingress.kubernetes.io/certificate-arn"           = var.aws_ingress_certificate_arn
      "alb.ingress.kubernetes.io/group.order"               = 10
      "alb.ingress.kubernetes.io/listen-ports"              = "[{\"HTTPS\":443}]"
      "alb.ingress.kubernetes.io/scheme"                    = "internet-facing"
      "alb.ingress.kubernetes.io/unhealthy-threshold-count" = 3
    }
    labels = local.app_labels
  }
  spec {
    ingress_class_name = "alb"
    rule {
      host = var.host_name
      http {
        path {
          backend {
            service {
              name = var.name
              port {
                number = 80
              }
            }
          }
          path      = "/"
          path_type = "Prefix"
        }
      }
    }
  }
}

resource "kubernetes_service" "this" {
  metadata {
    name      = var.name
    namespace = kubernetes_namespace.this.metadata[0].name
    labels    = local.app_labels
  }
  spec {
    type                    = "NodePort"
    internal_traffic_policy = "Cluster"
    ip_families             = ["IPv4"]
    ip_family_policy        = "SingleStack"
    port {
      name        = "http"
      protocol    = "TCP"
      port        = 80
      target_port = "http"
    }
    selector = {
      app = var.name
    }
  }
}

locals {
  policy_name = var.policy_name == "" ? "LiteLLM-BR-${data.aws_region.this.region}" : var.policy_name
  role_name   = var.role_name == "" ? "litellm-br-${data.aws_region.this.region}" : var.role_name
}

module "bedrock-policy" {
  source      = "../../../security/policy"
  name        = local.policy_name
  path        = "/"
  description = "LiteLLM Bedrock IAM Policy"
  policy_json = try(data.aws_iam_policy_document.bedrock-policy.json, {})
}

module "bedrock-oidc-role" {
  source = "../../../security/role/access-entry"
  name   = local.role_name
  policy_arns = {
    "BedrockPolicy" = module.bedrock-policy.policy_arn
  }
  cluster_name        = var.cluster_name
  cluster_policy_arns = {}
  # Restricted to specific service account instead of wildcard for least privilege
  oidc_principals = {
    "${var.cluster_oidc_provider_arn}" = ["system:serviceaccount:${var.namespace}:${var.name}"]
  }
  tags = var.tags
}

resource "kubernetes_service_account" "litellm" {
  metadata {
    name      = var.name
    namespace = kubernetes_namespace.this.metadata[0].name
    annotations = {
      "eks.amazonaws.com/role-arn" : module.bedrock-oidc-role.role_arn
    }
    labels = local.app_labels
  }
}

resource "kubernetes_secret" "postgres" {
  metadata {
    name      = var.db_url_secret_name
    namespace = kubernetes_namespace.this.metadata[0].name
    labels    = local.app_labels
  }
  data = {
    "${var.db_url_secret_key}" = var.db_url
  }
}

resource "kubernetes_secret" "redis" {
  metadata {
    name      = var.redis_host_secret_name
    namespace = kubernetes_namespace.this.metadata[0].name
    labels    = local.app_labels
  }
  data = {
    "${var.redis_host_secret_key}"     = var.redis_host
    "${var.redis_password_secret_key}" = var.redis_password
  }
}

resource "kubernetes_secret" "key" {
  metadata {
    name      = var.litellm_key_secret_name
    namespace = kubernetes_namespace.this.metadata[0].name
    labels    = local.app_labels
  }
  data = {
    "${var.litellm_key_master_secret_key}" = var.litellm_master_key
    "${var.litellm_key_salt_secret_key}"   = var.litellm_salt_key
  }
}

resource "kubernetes_secret" "gcloud" {
  metadata {
    name      = var.gcloud_auth_secret_name
    namespace = kubernetes_namespace.this.metadata[0].name
    labels    = local.app_labels
  }
  data = {
    "${var.gcloud_auth_secret_key}" = var.gcloud_auth
  }
}

resource "kubernetes_config_map" "config" {
  metadata {
    name      = var.litellm_config_name
    namespace = kubernetes_namespace.this.metadata[0].name
    labels    = local.app_labels
  }
  data = {
    "${var.litellm_config_key}" = templatefile("${path.module}/scripts/${var.litellm_config_key}", {
      GCP_CRED_PATH = "${var.gcloud_auth_file_path}/${var.gcloud_auth_secret_key}"
    })
  }
}

resource "kubernetes_config_map" "middleware" {
  metadata {
    name      = var.litellm_config_middleware_name
    namespace = kubernetes_namespace.this.metadata[0].name
    labels    = local.app_labels
  }
  data = {
    "${var.litellm_config_middleware_key}" = templatefile("${path.module}/scripts/${var.litellm_config_middleware_key}", {})
  }
}

locals {
  primary_env_vars = {
    AWS_REGION_NAME   = var.aws_bedrock_region
    DOCS_URL          = "/swagger"
    LITELLM_LOG       = "ERROR"
    LITELLM_LOG_LEVEL = "ERROR"
    LITELLM_MODE      = "PRODUCTION"
    REDIS_PORT        = "6379"
    REDIS_SSL         = "True"
  }
  secret_env_vars = {
    DATABASE_URL = {
      name = var.db_url_secret_name
      key  = var.db_url_secret_key
    }
    LITELLM_MASTER_KEY = {
      name = var.litellm_key_secret_name
      key  = var.litellm_key_master_secret_key
    }
    LITELLM_SALT_KEY = {
      name = var.litellm_key_secret_name
      key  = var.litellm_key_salt_secret_key
    }
    REDIS_HOST = {
      name = var.redis_host_secret_name
      key  = var.redis_host_secret_key
    }
    REDIS_PASSWORD = {
      name = var.redis_host_secret_name
      key  = var.redis_password_secret_key
    }
  }
}

resource "kubernetes_deployment" "litellm" {
  metadata {
    name      = var.name
    namespace = kubernetes_namespace.this.metadata[0].name
    labels = merge(local.app_labels, {
      app = var.name
    })
  }
  spec {
    replicas = var.replicas
    strategy {
      type = "RollingUpdate"
    }
    selector {
      match_labels = {
        app = var.name
      }
    }
    template {
      metadata {
        annotations = {}
        labels = {
          app = var.name
        }
      }
      spec {
        service_account_name = kubernetes_service_account.litellm.metadata[0].name
        container {
          name  = var.name
          image = "${var.image_repo}:${var.image_tag}"
          # Split command into array for better readability and maintainability
          command = ["litellm", "--port", tostring(var.app_container_port), "--config", "/app/${var.litellm_config_key}", "--detailed_debug"]
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
          port {
            container_port = var.app_container_port
            name           = "http"
            protocol       = "TCP"
          }
          resources {
            limits   = var.resource_limits
            requests = var.resource_requests
          }
          volume_mount {
            mount_path = "/app/${var.litellm_config_key}"
            name       = kubernetes_config_map.config.metadata[0].name
            # Changed to read_only for security best practices
            read_only = true
            sub_path  = var.litellm_config_key
          }
          volume_mount {
            mount_path = "/app/${var.litellm_config_middleware_key}"
            name       = kubernetes_config_map.middleware.metadata[0].name
            # Changed to read_only for security best practices
            read_only = true
            sub_path  = var.litellm_config_middleware_key
          }
          volume_mount {
            mount_path = var.gcloud_auth_file_path
            name       = kubernetes_secret.gcloud.metadata[0].name
            read_only  = true
            # Removed empty sub_path for proper volume mounting
          }
        }
        volume {
          name = kubernetes_config_map.config.metadata[0].name
          config_map {
            name = kubernetes_config_map.config.metadata[0].name
          }
        }
        volume {
          name = kubernetes_config_map.middleware.metadata[0].name
          config_map {
            name = kubernetes_config_map.middleware.metadata[0].name
          }
        }
        volume {
          name = kubernetes_secret.gcloud.metadata[0].name
          secret {
            secret_name = kubernetes_secret.gcloud.metadata[0].name
          }
        }
      }
    }
  }
}