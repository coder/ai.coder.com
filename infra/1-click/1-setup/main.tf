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
    external = {
      source = "hashicorp/external"
      version = ">= 2.3.5"
    }
  }
  # backend "s3" {}
}

##
# Remote State Resources
##

data "aws_vpc" "this" {
  tags = {
    "Name" = "${var.name}-${local.normalized_domain_name}"
  }
}

data "aws_db_instance" "coder" {
  db_instance_identifier = "${var.name}-${local.normalized_domain_name}-coder"
}

data "aws_db_instance" "litellm" {
  db_instance_identifier = "${var.name}-${local.normalized_domain_name}-litellm"
}

data "aws_db_instance" "grafana" {
  db_instance_identifier = "${var.name}-${local.normalized_domain_name}-grafana"
}

data "aws_security_group" "coder" {
  name = "${var.name}-${local.normalized_domain_name}-pgsql"
  vpc_id = data.aws_vpc.this.id
}

data "aws_eks_cluster" "coder" {
  name = "${var.name}-${local.normalized_domain_name}"
}

data "aws_eks_cluster_auth" "coder" {
  name = "${var.name}-${local.normalized_domain_name}"
}

data "aws_iam_openid_connect_provider" "coder" {
  url = data.aws_eks_cluster.coder.identity[0].oidc[0].issuer
}

##
# Global Inputs + Providers
##

variable "region" {
  description = "The AWS region of the deployment."
  type        = string
  default = "us-east-2"
}

variable "name" {
  description = "Name for created resources and tag prefix."
  type        = string
  default = "coder"
}

variable "profile" {
  type = string
  default = "default"
}

variable "domain_name" {
  type = string
}

provider "aws" {
  region  = var.region
  profile = var.profile
}

provider "helm" {
  kubernetes = {
    host                   = data.aws_eks_cluster.coder.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.coder.certificate_authority[0].data)
    token                  = data.aws_eks_cluster_auth.coder.token
  }
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.coder.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.coder.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.coder.token
}

data "aws_region" "this" {}

locals {
  normalized_domain_name = split(".", var.domain_name)[0]
}