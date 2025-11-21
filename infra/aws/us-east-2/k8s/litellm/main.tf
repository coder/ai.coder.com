terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "3.1.1"
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

variable "cluster_oidc_provider_arn" {
  type = string
}

variable "cluster_profile" {
  type    = string
  default = "default"
}

variable "addon_namespace" {
  type    = string
  default = "kube-system"
}

variable "aws_ingress_certificate_arn" {
  type      = string
  sensitive = true
}

variable "db_url" {
  type      = string
  sensitive = true
}

variable "litellm_salt_key" {
  type      = string
  sensitive = true
}

variable "litellm_master_key" {
  type      = string
  sensitive = true
}

variable "redis_host" {
  type      = string
  sensitive = true
}

variable "redis_password" {
  type      = string
  sensitive = true
}

variable "gcloud_auth" {
  type      = string
  sensitive = true
}

variable "host_name" {
  type      = string
  sensitive = true
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

provider "kubernetes" {
  host                   = data.aws_eks_cluster.this.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.this.token
}

module "litellm" {
  source = "../../../../../modules/k8s/bootstrap/litellm"

  cluster_name              = var.cluster_name
  cluster_oidc_provider_arn = var.cluster_oidc_provider_arn
  namespace                 = var.addon_namespace
  name                      = "litellm"
  host_name                 = var.host_name
  resource_limits = {
    cpu    = "2"
    memory = "4Gi"
  }
  replicas                    = 4
  aws_ingress_certificate_arn = var.aws_ingress_certificate_arn
  db_url                      = var.db_url
  litellm_salt_key            = var.litellm_salt_key
  litellm_master_key          = var.litellm_master_key
  redis_host                  = var.redis_host
  redis_password              = var.redis_password
  gcloud_auth                 = var.gcloud_auth
}

module "litellm-gen-key" {
  depends_on = [module.litellm]
  source     = "../../../../../modules/k8s/bootstrap/litellm-generate-key"

  cluster_name              = var.cluster_name
  cluster_oidc_provider_arn = var.cluster_oidc_provider_arn
  namespace                 = var.addon_namespace
  name                      = "rotate-key"
  image_repo                = var.rotate_key_image_repo
  image_tag                 = var.rotate_key_image_tag
  litellm_create_secret     = false
  litellm_url               = "https://${var.host_name}"
  secret_id                 = var.aws_secret_id
  secret_region             = var.aws_secret_region
}