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
  default = "cert-manager"
}

variable "addon_version" {
  type    = string
  default = "v1.18.2"
}