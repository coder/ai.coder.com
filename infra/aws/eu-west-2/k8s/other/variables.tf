variable "profile" {
  type    = string
  default = "default"
}

variable "region" {
  type    = string
  default = "us-east-2"
}

variable "cluster_name" {
  type = string
}

variable "azs" {
  type    = list(string)
  default = ["a", "b", "c"]
}