terraform {
  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "3.1.1"
    }
  }
}

variable "namespace" {
  description = "Kubernetes namespace where metrics-server will be deployed"
  type        = string
  default     = "kube-system"
}

variable "chart_version" {
  description = "Helm chart version for metrics-server"
  type        = string
  default     = "3.13.0"
}

variable "node_selector" {
  description = "Node labels for metrics-server pod placement"
  type        = map(string)
  default     = {}
}

resource "helm_release" "metrics-server" {
  name             = "metrics-server"
  namespace        = var.namespace
  chart            = "metrics-server"
  repository       = "https://kubernetes-sigs.github.io/metrics-server/"
  create_namespace = true
  skip_crds        = false
  wait             = true
  wait_for_jobs    = true
  version          = var.chart_version
  timeout          = 120 # in seconds

  values = [yamlencode({
    # Use variable instead of hardcoded value for flexibility
    nodeSelector = var.node_selector
  })]
}