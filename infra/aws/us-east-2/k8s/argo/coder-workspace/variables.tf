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

variable "coder_access_url" {
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