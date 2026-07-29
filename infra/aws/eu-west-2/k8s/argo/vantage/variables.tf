variable "region" {
  type = string
}

variable "controller_region" {
  type = string
}

variable "profile" {
  type    = string
  default = "default"
}

variable "cluster_name" {
  type = string
}

variable "vantage_api_token" {
  type      = string
  sensitive = true
  default   = ""
}