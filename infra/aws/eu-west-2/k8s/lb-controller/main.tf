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

variable "addon_namespace" {
  type    = string
  default = "default"
}

variable "addon_version" {
  type    = string
  default = "1.13.2"
}

variable "use_cert_manager" {
  type    = bool
  default = false
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

module "lb-controller" {
  source                    = "../../../../../modules/k8s/bootstrap/lb-controller"
  cluster_name              = data.aws_eks_cluster.this.name
  cluster_oidc_provider_arn = var.cluster_oidc_provider_arn

  namespace           = var.addon_namespace
  chart_version       = var.addon_version
  enable_cert_manager = var.use_cert_manager
  service_target_eni_sg_tags = {
    Name = "aidemo-node"
  }
  cluster_asg_node_labels = { # var.karpenter_node_labels
    "node.amazonaws.io/managed-by" = "asg"
  }
}