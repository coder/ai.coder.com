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
  type    = string
  default = "default"
}

variable "domain_name" {
  description = "Your Coder domain name (i.e. coder-example.com)"
  type        = string
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
  normalized_domain_name = split(".", var.domain_name)[0]
  tags_global            = {}
}

# If R53 enabled, then fetch service account from cert-manager for IAM Role
variable "r53_config" {
  description = "Enable to use Route53 as a DNS01 provider for ACME challenges."
  type = object({
    enabled = bool
  })
  default = {
    enabled     = false
  }
}

# If CF enabled, then fetch secret from cert-manager for token
variable "cf_config" {
  description = "Enable to use CloudFlare as a DNS01 provider for ACME challenges."
  type = object({
    enabled = bool
    email = string
    token = string
  })
  default = {
    enabled     = false
    email       = ""
    token = ""  
  }
  sensitive = true
}

variable "use_ext_dns" {
  description = "Toggle the K8s 'external-dns' addon. Disable in-case you want to manage DNS records yourself."
  type = bool
  default = true
}