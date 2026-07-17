variable "profile" {
  type    = string
  default = "default"
}

variable "region" {
  type    = string
  default = "us-east-2"
}

variable "vpc_name" {
  type = string
}

variable "private_subnet_suffix" {
  type    = string
  default = "private"
}

variable "cluster_name" {
  type = string
}

variable "cluster_issuer_name" {
  type    = string
  default = "issuer"
}

variable "cluster_issuer_priv_key_ref" {
  type    = string
  default = "issuer-account-key"
}

variable "azs" {
  type    = list(string)
  default = ["a", "b", "c"]
}

variable "cloudflare_api_token" {
  type      = string
  sensitive = true
}

variable "cloudflare_secret_namespace" {
  type    = string
  default = "cert-manager"
}

variable "cloudflare_email" {
  type = string
}
