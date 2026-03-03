terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "3.1.1"
    }
    kubernetes = {
      source = "hashicorp/kubernetes"
      version = "3.0.1"
    }
  }
}

variable "cluster_name" {
  type = string
  default = "aidemo-eks"
}

variable "cluster_region" {
  type = string
  default = "us-east-2"
}

variable "cluster_profile" {
  type    = string
  default = "demo-coder"
}

variable "namespace" {
  type    = string
  default = "litellm"
}

variable "chart_version" {
  type    = string
  default = "0.1.830"
  # 1.81.13
}

variable "cluster_oidc_provider_arn" {
  type = string
}

provider "aws" {
  region  = var.cluster_region
  profile = var.cluster_profile
}

data "aws_eks_cluster" "this" {
  name = var.cluster_name
}

data "aws_eks_cluster_auth" "this" {
  name = var.cluster_name
}

variable "tags" {
  type = map(string)
  default = {}
}

variable "replicas" {
  type    = number
  default = 1
}

variable "image_config" {
  type = object({
    repo = optional(string, "ghcr.io/berriai/litellm-database")
    pull_policy = optional(string, "IfNotPresent")
    tag = optional(string, "main-latest")
  })
  default = {}
}

variable "litellm_master_key" {
  type = string
  sensitive = true

  validation {
    condition     = startswith(var.litellm_master_key, "sk-")
    error_message = "The LiteLLM master key must start with 'sk-'."
  } 
}

variable "litellm_master_secret_name" {
  type = string
  default = "masterkey"
}

variable "db" {
  type = object({
    use_existing = optional(bool, false)
    secret_name = optional(string, "postgres")
    db_name = optional(string, "litellm")
    username      = optional(string, "litellm")
    admin_password = optional(string, "NoTaGrEaTpAsSwOrD")
    user_password  = optional(string, "NoTaGrEaTpAsSwOrD")
    endpoint = optional(string, "localhost")
  })
  default = {
    use_existing = false
    secret_name = "postgres"
    db_name = "litellm"
    username = "litellm"
    admin_password = "NoTaGrEaTpAsSwOrD"
    user_password = "NoTaGrEaTpAsSwOrD"
    endpoint = "localhost"
  }
  sensitive = true
}

variable "service_account_annotations" {
  type = map(string)
  default = {}
}

variable "service_lb_class" {
  type = string
  default = "service.k8s.aws/nlb"
}

variable "svc_annots" {
  type = map(string)
  default = {}
}

variable "svc_port" {
  type    = number
  default = 80
}

variable "health_port" {
  type    = number
  default = 8081
}

variable "proxy_config" {
  type = any
  default = {}
}

variable "env_vars" {
  type = map(string)
  default = {}
}

variable "mounts" {
  type = list(object({
    secret_name = optional(string, "")
    path = optional(string, "")
    read_only = optional(bool, false)
  }))
  default = []
}

variable "autoscaling_min_replicas" {
  type    = number
  default = 1
}

variable "autoscaling_max_replicas" {
  type    = number
  default = 5
}

variable "autoscaling_target_cpu_use" {
  type    = number
  description = "The target CPU utilization percentage for autoscaling."
  default = 80
}

variable "autoscaling_target_memory_use" {
  type    = number
  description = "The target memory utilization percentage for autoscaling."
  default = 80
}

variable "node_selector" {
  type = map(string)
  default = {}
}

variable "tolerations" {
  type = any
  default = {}
}

variable "affinity" {
  type = any
  default = {}
}

module "oidc-role" {
  source       = "../../../security/role/access-entry"
  name         = "LiteLLM-Bedrock"
  cluster_name = var.cluster_name
  policy_arns = {
    "AmazonBedrockLimitedAccess" = "arn:aws:iam::aws:policy/AmazonBedrockLimitedAccess"
  }
  cluster_policy_arns = {
    "AmazonEKSClusterAdminPolicy" = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  }
  oidc_principals = {
    "${var.cluster_oidc_provider_arn}" = ["system:serviceaccount:*:*"]
  }
  tags = var.tags
}

resource "kubernetes_namespace_v1" "litellm" {
  metadata {
    name = var.namespace
  }
}

resource "kubernetes_secret_v1" "master-key" {
  metadata {
    name      = var.litellm_master_secret_name
    namespace = kubernetes_namespace_v1.litellm.metadata[0].name
  }
  data = {
    password = var.litellm_master_key
  }
  type = "Opaque"
}

resource "kubernetes_secret_v1" "db-auth" {
  metadata {
    name      = nonsensitive(var.db.secret_name)
    namespace = kubernetes_namespace_v1.litellm.metadata[0].name
  }
  data = {
    username = nonsensitive(var.db.username)
    postgres-password = var.db.admin_password
    password = var.db.user_password
    endpoint = var.db.endpoint
  }
  type = "Opaque"
}

variable "access_url" {
  type    = string
  default = ""
}

variable "ssl_cert_config" {
  type = object({
    create_secret = optional(bool, true)
    name = optional(string, "ssl-certs")
    days_until_renewal = optional(number, 30)
  })
  default = {
    create_secret = true
    name = "ssl-certs"
    days_until_renewal = 30
  }
}

variable "mount_ssl" {
  type = object({
    enable = optional(bool, true)
    secret_name = optional(string, "ssl-cert")
    path = optional(string, "")
    key_name = optional(string, "tls.key")
    crt_name = optional(string, "tls.crt")
    pem_name = optional(string, "tls-combined.pem")
  })
  default = {
    enable = false
    name = "ssl-cert"
    path = "/tmp/ssl/ssl-cert"
    key_name = "tls.key"
    crt_name = "tls.crt"
    pem_name = "tls-combined.pem"
  }
}

variable "chart_name" {
  type = string
  default = "litellm-helm"
}

variable "release_name" {
  type = string
  default = "litellm"
}

locals {
  volumes = [ for v in var.mounts : merge(v.secret_name != "" ? {
    name = v.secret_name
    secret = {
      secretName = v.secret_name
      optional = false
    }
  } : null) ]
  volumeMounts = [ for v in var.mounts : merge(v.secret_name != "" ? {
    name = v.secret_name
    mountPath = v.path
    readOnly = v.read_only
  } : null) ]
}

resource "helm_release" "litellm" {
  name             = var.release_name
  namespace        = var.namespace
  chart            = var.chart_name
  repository       = "oci://ghcr.io/berriai"
  create_namespace = true
  upgrade_install  = true
  skip_crds        = false
  replace          = true
  wait             = true
  wait_for_jobs    = true
  reuse_values     = false
  version          = var.chart_version
  timeout          = 120 # in seconds

  values = [yamlencode({
    replicaCount = var.replicas
    image = {
      repository = var.image_config.repo
      pullPolicy = var.image_config.pull_policy
      tag = var.image_config.tag
    }
    imagePullSecrets = []
    nameOverride = "litellm"
    fullnameOverride = ""
    serviceAccount = {
      create = true
      automount = true
      annotations = merge({
        "eks.amazonaws.com/role-arn" = module.oidc-role.role_arn
      }, var.service_account_annotations)
    }
    service = {
      type = "LoadBalancer"
      loadBalancerClass = var.service_lb_class
      port = var.svc_port
      annotations = var.svc_annots
    }
    separateHealthApp = true
    separateHealthPort = var.health_port

    masterkeySecretName = kubernetes_secret_v1.master-key.metadata[0].name
    masterkeySecretKey = "password"

    proxyConfigMap = {
      create = true
    }

    proxy_config = var.proxy_config

    autoscaling = {
      enabled = true
      minReplicas = var.autoscaling_min_replicas
      maxReplicas = var.autoscaling_max_replicas
      targetCPUUtilizationPercentage = var.autoscaling_target_cpu_use
      targetMemoryUtilizationPercentage = var.autoscaling_target_memory_use
    }

    nodeSelector = var.node_selector
    tolerations = var.tolerations
    affinity = var.affinity

    db = {
      deployStandalone = var.db.endpoint == "localhost"
      useExisting = nonsensitive(var.db.use_existing)
      database = nonsensitive(var.db.db_name)
      url = "postgresql://$(DATABASE_USERNAME):$(DATABASE_PASSWORD)@$(DATABASE_HOST)/$(DATABASE_NAME)"
      secret = {
        name = kubernetes_secret_v1.db-auth.metadata[0].name
        usernameKey = "username"
        passwordKey = "password"
        # Optional: when set, DATABASE_HOST will be sourced from this secret key instead of db.endpoint
        endpointKey = "endpoint"
      }
      useStackgresOperator = false
    }

    # Settings for Bitnami postgresql chart (if db.deployStandalone is true, ignored otherwise)
    postgresql = {
      architecture = "standalone"
      auth = {
        username = var.db.username
        database = "litellm"
        enablePostgresUser = true

        # A secret is created by this chart (litellm-helm) with the credentials that the new Postgres instance should use.
        existingSecret = kubernetes_secret_v1.db-auth.metadata[0].name
        secretKeys = {
          adminPasswordKey = "postgres-password"
          userPasswordKey = "password"
        }
      }
    }

    redis = {
      enabled = false
      architecture = "standalone"
    }

    migrationJob = {
      enabled = true # Enable or disable the schema migration Job
      retries = 3 # Number of retries for the Job in case of failure
      backoffLimit = 4 # Backoff limit for Job restarts
      disableSchemaUpdate = false # Skip schema migrations for specific environments. When True, the job will exit with code 0.
      annotations = {}
      ttlSecondsAfterFinished = 120
      resources = {}
      #  requests:
      #    cpu: 100m
      #    memory: 100Mi
      extraContainers = []

      # Hook configuration
      hooks = {
        argocd = {
          enabled = false
        }
        helm = {
          enabled = false
        }
      }
    }


    envVars = merge({ 
      NO_DOCS = "False"
    }, var.mount_ssl.enable ? {
      SSL_CERT_FILE = "${var.mount_ssl.path}/${var.mount_ssl.pem_name}"
      SSL_KEYFILE_PATH = "${var.mount_ssl.path}/${var.mount_ssl.key_name}"
      SSL_CERTFILE_PATH = "${var.mount_ssl.path}/${var.mount_ssl.crt_name}"
      SSL_VERIFY = "False"
    } : {},
      var.env_vars
    )
    
    extraEnvVars = {}

    # Additional volumes on the output Deployment definition.

    volumes = concat(
      var.mount_ssl.enable ? [{
        name = var.mount_ssl.secret_name
        secret = {
          secretName = var.mount_ssl.secret_name
          optional = false
        }
      }] : [], 
      local.volumes
    )

    volumeMounts = concat(
      var.mount_ssl.enable ? [{
        name     = var.mount_ssl.secret_name
        mountPath = var.mount_ssl.path
        readOnly  = true
      }] : [], 
      local.volumeMounts
    )
  })]
}

output "namespace" {
  value       = kubernetes_namespace_v1.litellm.metadata[0].name
}