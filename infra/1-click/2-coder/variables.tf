variable "region" {
  description = "The AWS region of the deployment."
  type        = string
  default     = "us-east-2"
}

variable "azs" {
  type    = list(string)
  default = ["a", "b", "c"]
}

variable "name" {
  description = "Name for created resources and tag prefix."
  type        = string
  default     = "coder"
}

variable "profile" {
  type    = string
  default = "default"
}

variable "domain_name" {
  type = string
}

variable "coder_admin_email" {
  type    = string
  default = "admin@coder.com"
}

variable "coder_admin_password" {
  type      = string
  default   = "Th1s1sN0TS3CuR3!!"
  sensitive = true
}

variable "coder_license" {
  type      = string
  default   = ""
  sensitive = true
}

variable "coder_version" {
  type    = string
  default = "2.30.0"
}