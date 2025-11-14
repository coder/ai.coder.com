terraform {}

variable "name" {
  type = string
}

variable "annotations" {
  type    = map(string)
  default = {}
}

variable "storage_class_type" {
  type    = string
  default = "gp3"
  # Added validation because empty type causes StorageClass errors
  validation {
    condition     = var.storage_class_type != ""
    error_message = "storage_class_type must not be empty."
  }
}

variable "storage_class_provisioner" {
  type    = string
  default = "ebs.csi.aws.com"
}

variable "storage_class_reclaim_policy" {
  type    = string
  default = "Delete"
}

variable "storage_class_binding_mode" {
  type    = string
  default = "WaitForFirstConsumer"
  # Added validation because invalid binding mode causes Kubernetes API errors
  validation {
    condition     = contains(["Immediate", "WaitForFirstConsumer"], var.storage_class_binding_mode)
    error_message = "storage_class_binding_mode must be one of: Immediate, WaitForFirstConsumer."
  }
}

output "manifest" {
  value = yamlencode({
    apiVersion = "storage.k8s.io/v1"
    kind       = "StorageClass"
    metadata = {
      name        = var.name
      annotations = var.annotations
    }
    parameters = {
      type = var.storage_class_type
    }
    provisioner       = var.storage_class_provisioner
    reclaimPolicy     = var.storage_class_reclaim_policy
    volumeBindingMode = var.storage_class_binding_mode
  })
}