terraform {
  required_providers {
    coderd = {
      source = "coder/coderd"
    }
    random = {
      source = "hashicorp/random"
    }
  }
}

##
# Variables
##

variable "organization_id" {
  type    = string
  default = ""
}

variable "provisioner_key_name" {
  type    = string
  default = ""
}

variable "provisioner_tags" {
  type    = map(string)
  default = null
}

##
# Resources
##

resource "random_id" "provisioner_key_name" {
  # Regenerate ID when provisioner_key_name changes
  keepers = {
    provisioner_key_name = var.provisioner_key_name
  }
  byte_length = 8
}

locals {
  # Extract repeated conditional for readability because duplication reduces maintainability
  provisioner_key_name = var.provisioner_key_name == "" ? random_id.provisioner_key_name.id : var.provisioner_key_name
}

resource "coderd_provisioner_key" "key" {
  name            = local.provisioner_key_name
  organization_id = var.organization_id
  tags            = var.provisioner_tags
}

##
# Outputs
##

output "provisioner_key_name" {
  description = "Coder Provisioner Key Name"
  value       = local.provisioner_key_name
}

output "provisioner_key_secret" {
  description = "Coder Provisioner Key Secret"
  value       = coderd_provisioner_key.key.key
  sensitive   = true
}