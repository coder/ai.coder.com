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

variable "cluster_profile" {
  type    = string
  default = "default"
}

variable "addon_namespace" {
  type    = string
  default = "kube-system"
}

variable "addon_version" {
  type    = string
  default = "3.13.0"
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

module "metrics-server" {
  source = "../../../../../modules/k8s/bootstrap/metrics-server"

  namespace     = var.addon_namespace
  chart_version = var.addon_version
  node_selector = {
    "node.amazonaws.io/managed-by" = "asg"
  }
}