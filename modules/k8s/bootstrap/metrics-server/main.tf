terraform {
  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.17.0"
    }
  }
}

variable "namespace" {
  type    = string
  default = "kube-system"
}

variable "chart_version" {
  type    = string
  default = "3.13.0"
}

variable "node_selector" {
  type    = map(string)
  default = {}
}

variable "tolerations" {
  type = list(map(any))
  default = []
}

data "aws_region" "this" {}

data "aws_caller_identity" "this" {}

resource "helm_release" "metrics-server" {
  name             = "metrics-server"
  namespace        = var.namespace
  chart            = "metrics-server"
  repository       = "https://kubernetes-sigs.github.io/metrics-server/"
  create_namespace = true
  upgrade_install  = true
  skip_crds        = false
  wait             = true
  wait_for_jobs    = true
  version          = var.chart_version
  timeout          = 300 # in seconds

  values = [yamlencode({
    nodeSelector = var.node_selector
    tolerations = var.tolerations
  })]
}