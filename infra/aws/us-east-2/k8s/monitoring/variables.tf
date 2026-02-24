##
# Cluster Authentication Inputs
##

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

variable "namespace" {
  type    = string
  default = "observability"
}

variable "chart_timeout" {
  type    = number
  default = 360 # In Seconds
}

variable "chart_version" {
  type    = string
  default = "0.7.0-rc.1"
}

##
# Coder DB Inputs
##

variable "coder_db_rds_id" {
    type = string
}

variable "coder_db_username" {
  type      = string
  sensitive = true
}

variable "coder_db_password" {
  description = "Coder's DB password"
  type        = string
  sensitive   = true
}

##
# Coder Scraping Configs
##

variable "coderd_selector" {
  type    = string
  default = "pod=~`coder.*`, pod!~`.*provisioner.*`"
}

variable "provisionerd_selector" {
  type    = string
  default = "pod=~`coder-provisioner.*"
}

variable "coder_workspaces_selector" {
  type    = string
  default = "namespace=`coder-workspaces`"
}

variable "coderd_namespace" {
  type    = string
  default = "coder"
}

##
# Loki Inputs
##

variable "loki_s3_bucket_name" {
    type = string
}

variable "loki_s3_bucket_region" {
  type = string
}

##
# Grafana Inputs
##

variable "grafana_auth_username" {
  description = "Grafana Endpoint username"
  type        = string
  sensitive   = true
}

variable "grafana_auth_password" {
  description = "Grafana Endpoint password"
  type        = string
  sensitive   = true
}

variable "grafana_db_user" {
  description = "Grafana DB username"
  type        = string
  default     = "grafana"
}

variable "grafana_db_password" {
  description = "Grafana DB password"
  type        = string
  sensitive   = true
}

variable "grafana_db_rds_id" {
  description = "Grafana RDS DB ID"
  type        = string
}

variable "grafana_admin_username" {
  description = "Grafana Admin username"
  type        = string
  sensitive   = true
}

variable "grafana_admin_password" {
  description = "Grafana Admin password"
  type        = string
  sensitive   = true
}

variable "domain_name" {
  type = string
}

variable "vpc_name" {
  type = string
}

variable "azs" {
  type = list(string)
  default = ["a", "b", "c"]
}