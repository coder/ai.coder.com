variable "profile" {
  type = string
}

variable "region" {
  description = "The aws region for the vpc"
  type        = string
}

variable "cluster_name" {
  description = "Cluster name"
  type        = string
}

variable "azs" {
  type = list(string)
  default = ["a", "b", "c"]

  validation {
    condition = length(var.azs) <= 3
    error_message = "There should only be at most 3 availability zones specified."
  }
}

variable "vpc_name" {
  description = "Name for created resources and tag prefix"
  type        = string
}

variable "vpc_cidr" {
  type = string
  default = "10.0.0.0/16"
}

variable "private_subnet_suffix" {
  type = string
  default = "private"
}

variable "public_subnet_suffix" {
  type = string
  default = "public"
}

variable "nat_name" {
  description = "Name for created resources and tag prefix"
  type        = string
}