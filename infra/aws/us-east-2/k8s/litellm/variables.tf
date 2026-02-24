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

variable "addon_namespace" {
  type    = string
  default = "kube-system"
}

variable "db_rds_id" {
  type      = string
  sensitive = true
}

variable "db_admin_password" {
    type = string
    sensitive = true
}

variable "db_user_password" {
    type = string
    sensitive = true
}

variable "litellm_master_key" {
  type      = string
  sensitive = true
}

variable "gcloud_auth" {
  type      = string
  sensitive = true
}

variable "host_name" {
  type      = string
  sensitive = true
}

variable "vpc_name" {
  type = string
}

variable "azs" {
  type = list(string)
  default = ["a","b","c"]
}