variable "profile" {
  type    = string
  default = "default"
}

variable "region" {
  description = "The aws region to deploy eks cluster"
  type        = string
}

variable "vpc_name" {
  type = string
}

variable "private_subnet_suffix" {
  type    = string
  default = "private"
}

variable "public_subnet_suffix" {
  type    = string
  default = "public"
}