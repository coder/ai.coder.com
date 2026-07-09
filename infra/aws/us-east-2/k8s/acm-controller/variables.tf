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
  type = string
  default = "acm-chart"
}

variable "chart_name" {
  type = string
  default = "acm-chart"
}

variable "chart_version" {
  type = string
  default = "1.3.4"
}

variable "create_namespace" {
  type = bool
  default = true
}

variable "namespace" {
  type = string
  default = "acm-ctrl"
}