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

variable "addon_version" {
  type    = string
  default = "2.22.1"
}

variable "addon_namespace" {
  type    = string
  default = "default"
}

variable "addon_replace" {
  type    = bool
  default = false
}