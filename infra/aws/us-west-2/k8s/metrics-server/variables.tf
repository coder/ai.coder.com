variable "cluster_name" {
  type = string
}

variable "region" {
  type = string
}

variable "profile" {
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