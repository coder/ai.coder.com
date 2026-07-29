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
  type = string
}

variable "image_tag" {
  type    = string
  default = "latest"
}

variable "coder_token" {
  type      = string
  sensitive = true
}