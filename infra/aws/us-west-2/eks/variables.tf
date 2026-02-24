variable "profile" {
  type = string
}

variable "region" {
  description = "The aws region to deploy eks cluster"
  type        = string
}

variable "name" {
  description = "The resource name and tag prefix"
  type        = string
}

variable "eks_version" {
  description = "The eks version"
  type        = string
}

variable "instance_type" {
  description = "EKS Instance Size/Type"
  default     = "t3.xlarge"
  type        = string
}

variable "vpc_name" {
  type      = string
}

variable "private_subnet_suffix" {
  type      = string
  default = "private"
}

variable "public_subnet_suffix" {
  type      = string
  default = "public"
}