
##
# Global Inputs + Providers
##

variable "region" {
  description = "The AWS region of the deployment."
  type        = string
  default     = "us-east-2"
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

##
# Coder K8s Inputs
##

variable "coder_username" {
  description = "Coder DB's username."
  type        = string
  default     = "coder"
}

variable "coder_password" {
  description = "Coder DB's password."
  type        = string
  default     = "th1s1sn0tas3cur3pass0wrd"
  sensitive   = true
}

variable "coder_version" {
  type    = string
  default = "2.30.0"
}

variable "coder_license" {
  type      = string
  default   = ""
  sensitive = true
}

variable "coder_admin_email" {
  type    = string
  default = "admin@coder.com"
}

variable "coder_admin_username" {
  type    = string
  default = "admin"
}

variable "coder_admin_password" {
  type      = string
  default   = "Th1s1sN0TS3CuR3!!"
  sensitive = true
}

variable "grafana_username" {
  description = "Grafana DB's username."
  type        = string
  default     = "grafana"
}

variable "grafana_password" {
  description = "Grafana DB's password."
  type        = string
  default     = "th1s1sn0tas3cur3pass0wrd"
  sensitive   = true
}

variable "grafana_admin_username" {
  type    = string
  default = "admin"
}

variable "grafana_admin_password" {
  type      = string
  default   = "Th1s1sN0TS3CuR3!!"
  sensitive = true
}

variable "azs" {
  type    = list(string)
  default = ["a", "b", "c"]
}