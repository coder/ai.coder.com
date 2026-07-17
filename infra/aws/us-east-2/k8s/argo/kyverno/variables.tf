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

variable "release_name" {
  type    = string
  default = "kyverno"
}

variable "chart_name" {
  type    = string
  default = "kyverno"
}

variable "chart_version" {
  type    = string
  default = "3.7.1"
}

variable "create_namespace" {
  type    = bool
  default = true
}

variable "namespace" {
  type    = string
  default = "kyverno"
}