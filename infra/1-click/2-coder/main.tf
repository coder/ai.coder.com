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
      source  = "hashicorp/external"
      version = ">= 2.3.5"
    }
    http = {
      source  = "hashicorp/http"
    }
    coderd = {
      source  = "coder/coderd"
      version = "0.0.12"
    }
    time = {
      source = "hashicorp/time"
    }
    dns = {
      source = "hashicorp/dns"
    }
  }
}

##
# Remote State Resources
##

data "aws_vpc" "this" {
  tags = {
    "Name" = "${var.name}-${local.normalized_domain_name}"
  }
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
  default     = "us-east-2"
}

variable "name" {
  description = "Name for created resources and tag prefix."
  type        = string
  default     = "coder"
}

variable "profile" {
  type    = string
  default = "default"
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

provider "dns" {}

locals {
  normalized_domain_name = split(".", var.domain_name)[0]
}

##
# Login and Fetch Authentication Token
##

variable "domain_name" {
  type = string
}

variable "coder_admin_email" {
  type    = string
  default = "admin@coder.com"
}

variable "coder_admin_password" {
  type      = string
  default   = "Th1s1sN0TS3CuR3!!"
  sensitive = true
}

##
# Coder MUST be in a reachable state by now
##

data "aws_eip" "coder" {
  tags = {
    Name = "${var.name}-${local.normalized_domain_name}-coder-0"
  }
}

data "http" "login" {
  url = "https://${data.aws_eip.coder.public_ip}/api/v2/users/login"
  insecure = true
  method = "POST"
  request_headers = {
    Host = var.domain_name
    Accept = "application/json"
  }
  request_body = jsonencode({
    email    = var.coder_admin_email
    password = var.coder_admin_password
  })
}

provider "coderd" {
  url = "https://${var.domain_name}"
  token = jsondecode(data.http.login.response_body).session_token
}