variable "cluster_name" {
  type = string
}

variable "region" {
  type = string
}

variable "azs" {
  type    = list(string)
  default = ["a", "b", "c"]
}

variable "profile" {
  type    = string
  default = "default"
}