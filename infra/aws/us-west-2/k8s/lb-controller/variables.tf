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
  default = "default"
}

variable "addon_version" {
  type    = string
  default = "1.13.2"
}

variable "vpc_name" {
  type = string
}

variable "use_cert_manager" {
  type    = bool
  default = false
}