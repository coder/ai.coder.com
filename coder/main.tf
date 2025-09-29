terraform {
  required_providers {
    coderd = {
      source = "coder/coderd"
    }
    random = {
      source = "hashicorp/random"
    }
  }
  backend "s3" {}
}

variable "coder_token" {
  type      = string
  sensitive = true
}

variable "coder_primary_url" {
  type = string
}

variable "coder_username" {
  type      = string
  sensitive = true
}

provider "coderd" {
  url   = var.coder_primary_url
  token = var.coder_token
}

module "experiment-org" {
  source                    = "../modules/coder/org"
  provisioner_key_name      = "default"
  organization_name         = "experiment"
  organization_display_name = "Coder Experiments"
  organization_icon         = "/emojis/1f9d1-200d-1f52c.png"
  organization_description  = "Organization for Testing Coder Templates + Features"
}

module "demo-org" {
  source                    = "../modules/coder/org"
  provisioner_key_name      = "default"
  organization_name         = "demo"
  organization_display_name = "Internal Demos"
  organization_icon         = "/emojis/1f3a5.png" # 🎥
  organization_description  = "Organization for Doing Demo"
}