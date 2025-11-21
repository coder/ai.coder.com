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
    }
    coderd = {
      source = "coder/coderd"
    }
  }
  backend "s3" {}
}

variable "cluster_name" {
  type = string
}

variable "cluster_region" {
  type = string
}

variable "cluster_profile" {
  type    = string
  default = "default"
}

variable "cluster_oidc_provider_arn" {
  type = string
}

variable "provisioner_addon_version" {
  type    = string
  default = "2.23.0"
}

variable "logstream_addon_version" {
  type    = string
  default = "0.0.11"
}

variable "coder_access_url" {
  type      = string
  sensitive = true
}

variable "coder_token" {
  type      = string
  sensitive = true
}

variable "image_repo" {
  type      = string
  sensitive = true
}

variable "image_tag" {
  type    = string
  default = "latest"
}

variable "rotate_key_image_repo" {
  type      = string
  sensitive = true
}

variable "rotate_key_image_tag" {
  type      = string
  sensitive = true
}

variable "aws_secret_id" {
  type      = string
  sensitive = true
}

variable "aws_secret_region" {
  type      = string
  sensitive = true
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

provider "helm" {
  kubernetes = {
    host                   = data.aws_eks_cluster.this.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)
    token                  = data.aws_eks_cluster_auth.this.token
  }
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.this.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.this.token
}

provider "coderd" {
  url   = var.coder_access_url
  token = var.coder_token
}

locals {
  service_account_labels = {
    "app.kubernetes.io/instance" = "coder-provisioner"
    "app.kubernetes.io/name"     = "coder-provisioner"
    "app.kubernetes.io/part-of"  = "coder-provisioner"
  }
  node_selector = {
    "node.coder.io/managed-by" = "karpenter"
    "node.coder.io/used-for"   = "coder-provisioner"
  }
  tolerations = [{
    key      = "dedicated"
    operator = "Equal"
    value    = "coder-provisioner"
    effect   = "NoSchedule"
  }]
}

module "default-ws" {
  source                    = "../../../../../modules/k8s/bootstrap/coder-provisioner"
  cluster_name              = var.cluster_name
  cluster_oidc_provider_arn = var.cluster_oidc_provider_arn

  coder_organization_name = "coder"

  namespace                        = "coder-ws"
  image_repo                       = var.image_repo
  image_tag                        = var.image_tag
  ws_service_account_name          = "coder-ws"
  ws_service_account_labels        = local.service_account_labels
  provisioner_service_account_name = "coder"
  replica_count                    = 6
  primary_access_url               = var.coder_access_url
  env_vars = {
    CODER_PROMETHEUS_ENABLE              = "false"
    CODER_PROMETHEUS_COLLECT_AGENT_STATS = "false"
    CODER_PROMETHEUS_COLLECT_DB_METRICS  = "false"
  }
  node_selector = local.node_selector
  tolerations   = local.tolerations
}

module "default-ws-litellm-rotate-key" {
  depends_on = [module.default-ws]
  source     = "../../../../../modules/k8s/bootstrap/litellm-rotate-key"

  cluster_name              = var.cluster_name
  cluster_oidc_provider_arn = var.cluster_oidc_provider_arn
  namespace                 = "coder-ws"
  image_repo                = var.rotate_key_image_repo
  image_tag                 = var.rotate_key_image_tag
  secret_id                 = var.aws_secret_id
  secret_region             = var.aws_secret_region
}

module "experiment-ws" {
  source = "../../../../../modules/k8s/bootstrap/coder-provisioner"

  cluster_name              = var.cluster_name
  cluster_oidc_provider_arn = var.cluster_oidc_provider_arn

  coder_organization_name = "experiment"

  namespace                        = "coder-ws-experiment"
  image_repo                       = var.image_repo
  image_tag                        = var.image_tag
  ws_service_account_name          = "coder-ws-experiment"
  ws_service_account_labels        = local.service_account_labels
  provisioner_service_account_name = "coder"
  replica_count                    = 2
  primary_access_url               = var.coder_access_url
  env_vars = {
    CODER_PROMETHEUS_ENABLE              = "false"
    CODER_PROMETHEUS_COLLECT_AGENT_STATS = "false"
    CODER_PROMETHEUS_COLLECT_DB_METRICS  = "false"
  }
  node_selector = local.node_selector
  tolerations   = local.tolerations
}

module "experiment-ws-litellm-rotate-key" {
  depends_on = [module.experiment-ws]
  source     = "../../../../../modules/k8s/bootstrap/litellm-rotate-key"

  cluster_name              = var.cluster_name
  cluster_oidc_provider_arn = var.cluster_oidc_provider_arn
  namespace                 = "coder-ws-experiment"
  image_repo                = var.rotate_key_image_repo
  image_tag                 = var.rotate_key_image_tag
  secret_id                 = var.aws_secret_id
  secret_region             = var.aws_secret_region
}

module "demo-ws" {
  source = "../../../../../modules/k8s/bootstrap/coder-provisioner"

  cluster_name              = var.cluster_name
  cluster_oidc_provider_arn = var.cluster_oidc_provider_arn

  coder_organization_name = "demo"

  namespace                        = "coder-ws-demo"
  image_repo                       = var.image_repo
  image_tag                        = var.image_tag
  ws_service_account_name          = "coder-ws-demo"
  ws_service_account_labels        = local.service_account_labels
  provisioner_service_account_name = "coder"
  replica_count                    = 2
  primary_access_url               = var.coder_access_url
  env_vars = {
    CODER_PROMETHEUS_ENABLE              = "false"
    CODER_PROMETHEUS_COLLECT_AGENT_STATS = "false"
    CODER_PROMETHEUS_COLLECT_DB_METRICS  = "false"
  }
  node_selector = local.node_selector
  tolerations   = local.tolerations
}

module "demo-ws-litellm-rotate-key" {
  depends_on = [module.demo-ws]
  source     = "../../../../../modules/k8s/bootstrap/litellm-rotate-key"

  cluster_name              = var.cluster_name
  cluster_oidc_provider_arn = var.cluster_oidc_provider_arn
  namespace                 = "coder-ws-demo"
  image_repo                = var.rotate_key_image_repo
  image_tag                 = var.rotate_key_image_tag
  secret_id                 = var.aws_secret_id
  secret_region             = var.aws_secret_region
}