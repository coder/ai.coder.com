locals {
  CODER_TF_BACKEND_AWS_BUCKET_NAME = get_env("CODER_TF_BACKEND_AWS_BUCKET_NAME")
  CODER_TF_BACKEND_AWS_REGION = get_env("CODER_TF_BACKEND_AWS_REGION", "us-east-2")
  CODER_TF_BACKEND_AWS_PROFILE = get_env("CODER_TF_BACKEND_AWS_PROFILE", "default")
  CODER_TF_BACKEND_ENCRYPT = get_env("CODER_TF_BACKEND_ENCRYPT", "false")
  CODER_TF_USE_REMOTE_STATE = get_env("CODER_TF_USE_REMOTE_STATE", "false") == "true"

  CODER_AWS_PROFILE = get_env("CODER_AWS_PROFILE", "default")
  CODER_AWS_REGION = get_env("CODER_AWS_REGION", "us-east-2")
  CODER_AWS_AZS = get_env("CODER_AWS_AZS", jsonencode(["a", "c"]))

  CODER_DB_USERNAME = get_env("CODER_DB_USERNAME", "coder")
  CODER_DB_PASSWORD = get_env("CODER_DB_PASSWORD", "th1s1sn0tas3cur3pass0wrd")
  GRAFANA_DB_USERNAME = get_env("GRAFANA_DB_USERNAME", "grafana")
  GRAFANA_DB_PASSWORD = get_env("GRAFANA_DB_PASSWORD", "th1s1sn0tas3cur3pass0wrd")

  CODER_DOMAIN_NAME = get_env("CODER_DOMAIN_NAME")
  CODER_LICENSE = get_env("CODER_LICENSE", "")
  CODER_VERSION = get_env("CODER_VERSION", "2.30.0")

  CODER_USERNAME = get_env("CODER_USERNAME", "admin")
  CODER_EMAIL = get_env("CODER_EMAIL", "admin@coder.com")
  CODER_PASSWORD = get_env("CODER_PASSWORD", "Th1s1sN0TS3CuR3!!")

  GRAFANA_USERNAME = get_env("GRAFANA_ADMIN_USERNAME", "admin")
  GRAFANA_PASSWORD = get_env("GRAFANA_ADMIN_PASSWORD",  "Th1s1sN0TS3CuR3!!")
}

generate "backend" {
  path      = "backend.tf"
  if_exists = "overwrite"
  disable   = !local.CODER_TF_USE_REMOTE_STATE
  if_disabled = "remove_terragrunt"

  contents = <<-EOF
    terraform {
      backend "s3" {
        bucket = "${local.CODER_TF_BACKEND_AWS_BUCKET_NAME}"
        key            = "${path_relative_to_include()}/terraform.tfstate"
        region         = "${local.CODER_TF_BACKEND_AWS_REGION}"
        profile        = "${local.CODER_TF_BACKEND_AWS_PROFILE}"
        encrypt        = "${local.CODER_TF_BACKEND_ENCRYPT}"
      }
    }
  EOF
}

generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite"

  contents = <<-EOF
    terraform {
      required_version = ">= 1.0"
      required_providers {
        aws = {
          source  = "hashicorp/aws"
          version = "~> 6.32.1"
        }
        helm = {
          source  = "hashicorp/helm"
          version = "~> 3.1.1"
        }
        kubernetes = {
          source = "hashicorp/kubernetes"
          version = "~> 3.0.1"
        }
        external = {
          source = "hashicorp/external"
          version = "~> 2.3.5"
        }
        time = {
          source = "hashicorp/time"
          version = "~> 0.13.1"
        }
        http = {
          source = "hashicorp/http"
          version = "~> 3.5.0"
        }
        dns = {
          source = "hashicorp/dns"
          version = "~> 3.5.0"
        }
        archive = {
          source = "hashicorp/archive"
          version = "~> 2.7.1"
        }
        random = {
          source = "hashicorp/random"
          version = "~> 3.8.1"
        }
        coderd = {
          source  = "coder/coderd"
          version = "~> 0.0.12"
        }
      }
    }
  EOF
}