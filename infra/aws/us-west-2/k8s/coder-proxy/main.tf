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
    acme = {
      source = "vancluever/acme"
    }
    tls = {
      source = "hashicorp/tls"
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

variable "acme_server_url" {
  type    = string
  default = "https://acme-v02.api.letsencrypt.org/directory"
}

variable "acme_registration_email" {
  type = string
}

variable "addon_version" {
  type    = string
  default = "2.25.1"
}

variable "coder_proxy_name" {
  type = string
}

variable "coder_proxy_display_name" {
  type = string
}

variable "coder_proxy_icon" {
  type = string
}

variable "coder_access_url" {
  type = string
  # sensitive = true
}

variable "coder_proxy_url" {
  type = string
  # sensitive = true
}

variable "coder_proxy_wildcard_url" {
  type = string
  # sensitive = true
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

variable "kubernetes_ssl_secret_name" {
  type = string
}

variable "kubernetes_create_ssl_secret" {
  type    = bool
  default = true
}

variable "cloudflare_api_token" {
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

provider "acme" {
  server_url = var.acme_server_url
}

module "coder-proxy" {
  source = "../../../../../modules/k8s/bootstrap/coder-proxy"

  namespace                = "coder-proxy"
  acme_registration_email  = var.acme_registration_email
  acme_days_until_renewal  = 90
  replica_count            = 2
  helm_version             = var.addon_version
  image_repo               = var.image_repo
  image_tag                = var.image_tag
  primary_access_url       = var.coder_access_url
  proxy_access_url         = var.coder_proxy_url
  proxy_wildcard_url       = var.coder_proxy_wildcard_url
  coder_proxy_name         = var.coder_proxy_name
  coder_proxy_display_name = var.coder_proxy_display_name
  coder_proxy_icon         = var.coder_proxy_icon
  proxy_token_config = {
    name = "coder-proxy"
  }
  cloudflare_api_token = var.cloudflare_api_token
  ssl_cert_config = {
    name          = var.kubernetes_ssl_secret_name
    create_secret = var.kubernetes_create_ssl_secret
  }
  service_annotations = {
    "service.beta.kubernetes.io/aws-load-balancer-nlb-target-type" = "instance"
    "service.beta.kubernetes.io/aws-load-balancer-scheme"          = "internet-facing"
    "service.beta.kubernetes.io/aws-load-balancer-attributes"      = "deletion_protection.enabled=true"
  }
  node_selector = {
    "node.coder.io/managed-by" = "karpenter"
    "node.coder.io/used-for"   = "coder-proxy"
  }
  tolerations = [{
    key      = "dedicated"
    operator = "Equal"
    value    = "coder-proxy"
    effect   = "NoSchedule"
  }]
  topology_spread_constraints = [{
    max_skew           = 1
    topology_key       = "kubernetes.io/hostname"
    when_unsatisfiable = "ScheduleAnyway"
    label_selector = {
      match_labels = {
        "app.kubernetes.io/name"    = "coder"
        "app.kubernetes.io/part-of" = "coder"
      }
    }
    match_label_keys = [
      "app.kubernetes.io/instance"
    ]
  }]
  pod_anti_affinity_preferred_during_scheduling_ignored_during_execution = [{
    weight = 100
    pod_affinity_term = {
      label_selector = {
        match_labels = {
          "app.kubernetes.io/instance" = "coder-v2"
          "app.kubernetes.io/name"     = "coder"
          "app.kubernetes.io/part-of"  = "coder"
        }
      }
      topology_key = "kubernetes.io/hostname"
    }
  }]
}

import {
  id = "coder-proxy"
  to = module.coder-proxy.kubernetes_namespace.this
}