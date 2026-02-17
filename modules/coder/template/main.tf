terraform {
  required_version = ">= 1.0"
  required_providers {
    coderd = {
      source  = "coder/coderd"
      version = "0.0.12"
    }
    archive = {
        source = "hashicorp/archive"
    }
    time = {
      source = "hashicorp/time"
    }
  }
}

variable "template_config" {
    type = object({
        name = string
        display_name = string
        dir = string
        description = string
        icon = string
        org_id = string
        tf_vars = optional(list(object({
            name = string
            value = string
        })), [])
    })   
}

variable "archive_config" {
    type = object({
        type = optional(string, "zip")
        excludes = optional(list(string), [])
        output_path = string
    })
}

variable "time_static_triggers" {
    type = map(string)
    default = {}
}

data "archive_file" "this" {
  type        = var.archive_config.type
  excludes    = var.archive_config.excludes
  source_dir  = var.template_config.dir
  output_path = var.archive_config.output_path
}

resource "time_static" "this" {
  triggers = merge({
    run_on_checksum   = "${data.archive_file.this.id}"
    run_on_tf_vars = jsonencode(var.template_config.tf_vars)
  }, var.time_static_triggers)
}

resource "coderd_template" "this" {
  name            = var.template_config.name
  organization_id = var.template_config.org_id
  display_name    = var.template_config.display_name
  description     = var.template_config.description
  icon            = var.template_config.icon
  versions = [
    {
      name        = "stable-${formatdate("YYYY-MM-DD_hh-mm-ss", time_static.this.rfc3339)}"
      description = "The stable version of the template."
      directory   = var.template_config.dir
      active      = true
      tf_vars = toset(var.template_config.tf_vars)
    }
  ]
}