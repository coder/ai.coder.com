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

variable "addon_version" {
  type    = string
  default = "2.23.0"
}

variable "logstream_addon_version" {
  type    = string
  default = "0.0.11"
}

variable "coder_access_url" {
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