##
# AWS Provider Inputs
##

variable "region" {
  description = "The aws region for database deployment"
  type        = string
}

variable "profile" {
  type = string
}

##
# Loki Inputs
##

variable "loki_s3_bucket_name" {
  type = string
}

variable "loki_s3_bucket_tags" {
  type    = map(string)
  default = {}
}