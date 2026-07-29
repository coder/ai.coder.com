variable "profile" {
  type    = string
  default = "default"
}

variable "region" {
  description = "The aws region to deploy eks cluster"
  type        = string
}

variable "prometheus_endpoint" {
  type = string
}

variable "grafana_endpoint" {
  type = string
}

variable "grafana_token" {
  type      = string
  sensitive = true
}

variable "grafana_db_user" {
  description = "Grafana DB username"
  type        = string
}

variable "coder_db_rds_id" {
  type = string
}

variable "cluster_name" {
  type = string
}