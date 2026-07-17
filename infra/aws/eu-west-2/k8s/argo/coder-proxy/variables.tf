variable "region" {
  type = string
}

variable "profile" {
  type    = string
  default = "default"
}

variable "azs" {
  type    = list(string)
  default = ["a", "b", "c"]
}

variable "vpc_name" {
  type = string
}

variable "cluster_name" {
  type = string
}

variable "addon_version" {
  type    = string
  default = "2.25.1"
}

variable "coder_proxy_name" {
  type = string
}

variable "coder_proxy_display_name" {
  type = string
}

variable "coder_proxy_icon" {
  type = string
}

variable "coder_access_url" {
  type = string
}

variable "coder_proxy_url" {
  type = string
}

variable "coder_proxy_wildcard_url" {
  type = string
}

variable "image_repo" {
  type      = string
  sensitive = true
}

variable "image_tag" {
  type    = string
  default = "latest"
}

variable "coder_admin_email" {
  type = string
}

variable "coder_admin_password" {
  type      = string
  sensitive = true
}