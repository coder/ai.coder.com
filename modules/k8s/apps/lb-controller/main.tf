terraform {
  required_providers {
    local = {
      source  = "hashicorp/local"
      version = "~> 2.0"
    }
  }
}

variable "path" {
  description = "Directory path where AWS Load Balancer Controller manifests will be generated"
  type        = string
  validation {
    condition     = length(var.path) > 0
    error_message = "Path must not be empty"
  }
}

variable "namespace" {
  description = "Kubernetes namespace where AWS Load Balancer Controller will be deployed"
  type        = string
  validation {
    condition     = length(var.namespace) > 0
    error_message = "Namespace must not be empty"
  }
}

variable "aws_lb_controller_helm_version" {
  description = "Version of the AWS Load Balancer Controller Helm chart to deploy"
  type        = string
  validation {
    condition     = length(var.aws_lb_controller_helm_version) > 0
    error_message = "AWS Load Balancer Controller Helm version must not be empty"
  }
}

variable "cluster_name" {
  description = "EKS cluster name for AWS Load Balancer Controller to manage"
  type        = string
  validation {
    condition     = length(var.cluster_name) > 0
    error_message = "Cluster name must not be empty"
  }
}

variable "enable_cert_manager" {
  description = "Enable cert-manager for TLS certificate management"
  type        = bool
  default     = false
}

variable "service_target_eni_sg_tags" {
  description = "Security group tags for service target ENIs (used for NLB target groups)"
  type        = map(string)
  default     = {}
}

variable "service_account_annotations" {
  description = "Annotations for AWS Load Balancer Controller service account (e.g., IAM role)"
  type        = map(string)
  default     = {}
}

variable "cluster_asg_node_labels" {
  description = "Node labels for AWS Load Balancer Controller pod placement"
  type        = map(string)
  default     = {}
}

locals {
  service_target_eni_sg_tags = join(",", [
    for k, v in var.service_target_eni_sg_tags : "${k}=${v}"
  ])
}

module "kustomization" {
  source    = "../../objects/kustomization"
  namespace = var.namespace
  helm_charts = [{
    name         = "aws-load-balancer-controller"
    release_name = "eks"
    repo         = "https://aws.github.io/eks-charts"
    namespace    = var.namespace
    include_crds = true
    version      = var.aws_lb_controller_helm_version
    values_file  = "./values.yaml"
  }]
}

resource "local_file" "kustomization" {
  filename = "${var.path}/kustomization.yaml"
  content  = module.kustomization.manifest
}

resource "local_file" "values" {
  filename = "${var.path}/values.yaml"
  content = yamlencode({
    clusterName = var.cluster_name
    serviceAccount = {
      create                       = true
      annotations                  = var.service_account_annotations
      automountServiceAccountToken = true
      imagePullSecrets             = []
    }
    nodeSelector           = var.cluster_asg_node_labels
    enableCertManager      = var.enable_cert_manager
    serviceTargetENISGTags = local.service_target_eni_sg_tags
  })
}

output "namespace" {
  description = "The Kubernetes namespace where AWS Load Balancer Controller is deployed"
  value       = var.namespace
}

output "cluster_name" {
  description = "The EKS cluster name that AWS Load Balancer Controller manages"
  value       = var.cluster_name
}

output "helm_version" {
  description = "The version of the AWS Load Balancer Controller Helm chart deployed"
  value       = var.aws_lb_controller_helm_version
}

output "cert_manager_enabled" {
  description = "Whether cert-manager integration is enabled"
  value       = var.enable_cert_manager
}

output "manifest_path" {
  description = "The directory path where Kubernetes manifests are generated"
  value       = var.path
}