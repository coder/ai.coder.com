variable "profile" {
  type    = string
  default = "default"
}

variable "region" {
  type = string
}

variable "cluster_name" {
  type = string
}

variable "cluster_node_iam_role_name" {
  type = string
}

variable "vpc_name" {
  type = string
}

variable "private_subnet_suffix" {
  type    = string
  default = "private"
}