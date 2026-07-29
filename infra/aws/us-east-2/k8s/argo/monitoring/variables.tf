variable "region" {
  type = string
}

variable "profile" {
  type    = string
  default = "default"
}

variable "cluster_name" {
  type = string
}

variable "prometheus_endpoint" {
  type = string
}

variable "loki_s3_bucket_name" {
  type = string
}

variable "loki_s3_bucket_region" {
  type = string
}

variable "coder_db_rds_id" {
  type = string
}

variable "grafana_db_user" {
  type = string
}

variable "azs" {
  type    = list(string)
  default = ["a", "b", "c"]
}