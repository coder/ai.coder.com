terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.17.0"
    }
    kubernetes = {
      source = "hashicorp/kubernetes"
    }
  }
}

variable "release_name" {
  description = "The release name of the installed Helm app."
  type = string
  default = "coder-logstream-kube"
}

variable "chart_name" {
  description = "The chart name of the installed Helm app."
  type = string
  default = "coder-logstream-kube"
}

variable "helm_timeout" {
  type    = number
  default = 300 # In Seconds
}

variable "chart_version" {
  type    = string
  default = "v0.0.14"
}

variable "namespace" {
  type = string
  default = "coder-logstream-kube"
}

variable "image_repo" {
  type = string
  default = "ghcr.io/coder/coder-logstream-kube"
}

variable "image_tag" {
  type = string
  default = "v0.0.14"
}

variable "image_pull_policy" {
  type = string
  default = "IfNotPresent"
}

variable "coder" {
  type = object({
    access_url = string
    ws_ns = optional(list(string), [])
  })
}

variable "node_selector" {
  type = map(string)
  default = {}
}

variable "affinity" {
  type = any
  default = {}
}

variable "tolerations" {
  type = list(any)
  default = []
}

resource "kubernetes_namespace_v1" "logstream" {
  metadata {
    name = var.namespace
  }
}

resource "helm_release" "coder-logstream" {

  name             = var.release_name
  namespace        = kubernetes_namespace_v1.logstream.metadata[0].name
  chart            = var.chart_name
  repository       = "https://helm.coder.com/logstream-kube"
  create_namespace = false
  upgrade_install  = true
  skip_crds        = false
  wait             = true
  wait_for_jobs    = true
  version          = var.chart_version
  timeout          = var.helm_timeout

  values = [yamlencode({
    url = var.coder.access_url
    namespaces = var.coder.ws_ns
    image = {
      repo = var.image_repo
      tag = var.image_tag
      pullPolicy = var.image_pull_policy
    }
    
    nodeSelector = var.node_selector
    affinity = var.affinity
    tolerations = var.tolerations
  })]
}

output "namespace" {
    value = kubernetes_namespace_v1.logstream.metadata[0].name
}