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

variable "argocd_server_url" {
  type = string
}