terraform {
  required_providers {
    coderd = {
      source = "coder/coderd"
      # Added version constraint for reproducibility and maintainability
      version = ">= 1.0"
    }
  }
}

##
# Variables
##

variable "provisioner_key_name" {
  type    = string
  default = "default"
}

variable "organization_name" {
  type = string
}

variable "organization_display_name" {
  type = string
}

variable "organization_description" {
  description = "Description for the Coder organization"
  type        = string
}

variable "organization_icon" {
  description = "Icon URL for the Coder organization"
  type        = string
}

##
# Resources
##

resource "coderd_organization" "this" {
  name         = var.organization_name
  display_name = var.organization_display_name
  description  = var.organization_description
  icon         = var.organization_icon
}

module "default-provisioner" {
  source               = "../provisioner"
  organization_id      = coderd_organization.this.id
  provisioner_key_name = var.provisioner_key_name
}

##
# Outputs
##

output "organization_name" {
  value = coderd_organization.this.name
}

output "organization_id" {
  value = coderd_organization.this.id
}

output "provisioner_key_name" {
  value = module.default-provisioner.provisioner_key_name
}

output "provisioner_key_secret" {
  value     = module.default-provisioner.provisioner_key_secret
  sensitive = true
}