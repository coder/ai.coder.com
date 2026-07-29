variable "coder_token" {
  type      = string
  sensitive = true
}

variable "coder_primary_url" {
  type = string
}

variable "region" {
  type    = string
  default = "us-east-2"
}

variable "profile" {
  type    = string
  default = "demo-coder"
}