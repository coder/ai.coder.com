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

variable "registry_config" {
  type = object({
    url = optional(string, "oci://ghcr.io")
    username = string
    password = string
  })
  sensitive = true
}

provider "helm" {
  kubernetes = {
    host                   = data.aws_eks_cluster.this.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)
    token                  = data.aws_eks_cluster_auth.this.token
  }
  registries = [{
    url      = nonsensitive(var.registry_config.url)
    username = nonsensitive(var.registry_config.username)
    password = var.registry_config.password
  }]
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

variable "db_config" {
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

variable "service_annotations" {
  type = map(string)
  default = {}
}

variable "service_port" {
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

variable "volumes" {
  type = list(any)
  default = []
}

variable "volume_mounts" {
  type = list(any)
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
    name      = nonsensitive(var.db_config.secret_name)
    namespace = kubernetes_namespace_v1.litellm.metadata[0].name
  }
  data = {
    username = nonsensitive(var.db_config.username)
    postgres-password = var.db_config.admin_password
    password = var.db_config.user_password
    endpoint = var.db_config.endpoint
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

locals {
  common_name = replace(replace(var.access_url, "https://", ""), "http://", "")
}

resource "kubernetes_manifest" "cert" {

  count = var.ssl_cert_config.create_secret ? 1 : 0

  field_manager {
    force_conflicts = true
  }
  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind       = "Certificate"
    metadata = {
      labels    = {} # var.cert_labels
      name      = var.ssl_cert_config.name
      namespace = kubernetes_namespace_v1.litellm.metadata[0].name
    }
    spec = {
      secretName  = var.ssl_cert_config.name
      commonName  = local.common_name
      dnsNames    = [local.common_name]
      duration    = "${var.ssl_cert_config.days_until_renewal * 24}h"
      renewBefore = "8h"
      additionalOutputFormats = [{
        type = "CombinedPEM"
      },{
        type = "DER"
      }]
      issuerRef = {
        kind = "ClusterIssuer"
        name = "issuer"
      }
    }
  }
}

locals {
  ssl_volume = var.ssl_cert_config.create_secret ? {} : {}
}

variable "gcloud_auth" {
  type      = string
  sensitive = true
}

resource "kubernetes_secret_v1" "gcloud" {
  metadata {
    name      = "gcloud-auth"
    namespace = kubernetes_namespace_v1.litellm.metadata[0].name
    labels    = {}
  }
  data = {
    "service_account.json" = var.gcloud_auth
  }
}

resource "helm_release" "litellm" {
  name             = "litellm"
  namespace        = var.namespace
  chart            = "litellm-helm"
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
      port = var.service_port
      annotations = var.service_annotations
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
      deployStandalone = var.db_config.endpoint == "localhost"
      useExisting = nonsensitive(var.db_config.use_existing)
      database = nonsensitive(var.db_config.db_name)
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
        username = var.db_config.username
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
    }, merge(var.access_url != "" ? {
      # PROXY_BASE_URL = "${var.access_url}"
    } : {}, var.ssl_cert_config.create_secret ? {
      SSL_CERT_FILE = "/tmp/ssl/${local.common_name}/tls-combined.pem"
      SSL_KEYFILE_PATH = "/tmp/ssl/${local.common_name}/tls.key"
      SSL_CERTFILE_PATH = "/tmp/ssl/${local.common_name}/tls.crt"
      SSL_VERIFY = "False"
    } : {}))
    
    extraEnvVars = {}

    # Additional volumes on the output Deployment definition.
    volumes = [{
      name = kubernetes_manifest.cert[0].manifest.metadata.name
      secret = {
        secretName = kubernetes_manifest.cert[0].manifest.metadata.name
        optional = false
      }
    },{
      name = kubernetes_secret_v1.gcloud.metadata[0].name
      secret = {
        secretName = kubernetes_secret_v1.gcloud.metadata[0].name
        optional = false
      }
    }]

    # Additional volumeMounts on the output Deployment definition.
    volumeMounts = [{
      name     = kubernetes_manifest.cert[0].manifest.metadata.name
      mountPath = "/tmp/ssl/${local.common_name}"
      readOnly  = true
    },{
      name     = kubernetes_secret_v1.gcloud.metadata[0].name
      mountPath = "/tmp/gcloud/"
      readOnly  = true
    },]
  })]
}

output "namespace" {
  value       = kubernetes_namespace_v1.litellm.metadata[0].name
}