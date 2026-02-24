variable "region" {
  description = "The AWS region to deploy AWS-resources to."
  type        = string
  default     = "us-east-2"
}

variable "name" {
  description = "Name for created resources and it's tag prefix"
  type        = string
  default     = "coder"
}

variable "profile" {
  description = "The local AWS profile to use."
  type        = string
  default     = "default"
}

variable "domain_name" {
  description = "Your domain name (i.e. coder-example.com)."
  type        = string
}

variable "azs" {
  type    = list(string)
  default = ["a", "b", "c"]
}

variable "coder_username" {
  description = "Coder DB's username."
  type        = string
  default     = "coder"
}

variable "coder_password" {
  description = "Coder DB's password."
  type        = string
  sensitive   = true
  default     = "th1s1sn0tas3cur3pass0wrd"
}

variable "grafana_username" {
  description = "Grafana DB's username."
  type        = string
  default     = "grafana"
}

variable "grafana_password" {
  description = "Grafana DB's password."
  type        = string
  sensitive   = true
  default     = "th1s1sn0tas3cur3pass0wrd"
}

variable "loki_s3_bucket_tags" {
  type    = map(string)
  default = {}
}