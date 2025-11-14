terraform {
  required_providers {
    local = {
      source  = "hashicorp/local"
      version = "~> 2.0"
    }
  }
}

variable "path" {
  description = "Directory path where EBS CSI driver manifests will be generated"
  type        = string
  validation {
    condition     = length(var.path) > 0
    error_message = "Path must not be empty"
  }
}

variable "namespace" {
  description = "Kubernetes namespace where EBS CSI driver will be deployed"
  type        = string
  validation {
    condition     = length(var.namespace) > 0
    error_message = "Namespace must not be empty"
  }
}

variable "ebs_controller_helm_version" {
  description = "Version of the AWS EBS CSI driver Helm chart to deploy"
  type        = string
  validation {
    condition     = length(var.ebs_controller_helm_version) > 0
    error_message = "EBS controller Helm version must not be empty"
  }
}

variable "service_account_annotations" {
  description = "Annotations for EBS CSI driver service account (e.g., IAM role)"
  type        = map(string)
  default     = {}
}

variable "storage_class_name" {
  description = "Name of the Kubernetes storage class to create for EBS volumes"
  type        = string
  validation {
    condition     = length(var.storage_class_name) > 0
    error_message = "Storage class name must not be empty"
  }
}

variable "storage_class_type" {
  description = "EBS volume type for the storage class (gp2, gp3, io1, io2, sc1, st1)"
  type        = string
  default     = "gp3"
  validation {
    condition     = contains(["gp2", "gp3", "io1", "io2", "sc1", "st1"], var.storage_class_type)
    error_message = "Storage class type must be one of: gp2, gp3, io1, io2, sc1, st1"
  }
}

variable "storage_class_annotations" {
  description = "Annotations to apply to the storage class"
  type        = map(string)
  default     = {}
}

locals {
  kustomization_file = "kustomization.yaml"
  storage_class_file = "storage-class.yaml"
  values_file        = "values.yaml"
}

module "storageclass" {
  source = "../../../../modules/k8s/objects/storageclass"

  name               = var.storage_class_name
  annotations        = var.storage_class_annotations
  storage_class_type = var.storage_class_type
}

resource "local_file" "storage_class" {
  filename = join("/", [var.path, local.storage_class_file])
  content  = module.storageclass.manifest
}

module "kustomization" {
  source = "../../../../modules/k8s/objects/kustomization"

  namespace = var.namespace
  helm_charts = [{
    name         = "aws-ebs-csi-driver"
    release_name = "ebs-controller"
    namespace    = var.namespace
    version      = var.ebs_controller_helm_version
    repo         = "https://kubernetes-sigs.github.io/aws-ebs-csi-driver"
    values_file  = "./${local.values_file}"
  }]
  resources = []
}

resource "local_file" "kustomization" {
  filename = join("/", [var.path, local.kustomization_file])
  content  = module.kustomization.manifest
}

resource "local_file" "values" {
  filename = join("/", [var.path, local.values_file])
  content = yamlencode({
    controller = {
      serviceAccount = {
        annotations = var.service_account_annotations
      }
    }
  })
}

output "namespace" {
  description = "The Kubernetes namespace where EBS CSI driver is deployed"
  value       = var.namespace
}

output "helm_version" {
  description = "The version of the AWS EBS CSI driver Helm chart deployed"
  value       = var.ebs_controller_helm_version
}

output "storage_class_name" {
  description = "The name of the Kubernetes storage class created for EBS volumes"
  value       = var.storage_class_name
}

output "storage_class_type" {
  description = "The EBS volume type configured for the storage class"
  value       = var.storage_class_type
}

output "manifest_path" {
  description = "The directory path where Kubernetes manifests are generated"
  value       = var.path
}