terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.46"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 3.1.1"
    }
    kubernetes = {
      source = "hashicorp/kubernetes"
    }
  }
  # backend "s3" {}
}

##
# Global Inputs + Providers
##

variable "region" {
  description = "The AWS region"
  type        = string
  default     = "us-east-2"
}

variable "name" {
  description = "Name for created resources and tag prefix"
  type        = string
  default     = "coder"
}

variable "profile" {
  type = string
  default = "default"
}

data "aws_eks_cluster_auth" "coder" {
  name = module.eks.cluster_name
}

provider "aws" {
  region  = var.region
  profile = var.profile
}

provider "helm" {
  kubernetes = {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
    token                  = data.aws_eks_cluster_auth.coder.token
  }
}

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  token                  = data.aws_eks_cluster_auth.coder.token
}

locals {
  tags_global = {}
}