locals {
  CODER_TF_BACKEND_AWS_BUCKET_NAME = get_env("CODER_TF_BACKEND_AWS_BUCKET_NAME")
  CODER_TF_BACKEND_AWS_REGION      = get_env("CODER_TF_BACKEND_AWS_REGION")
  CODER_TF_BACKEND_AWS_PROFILE     = get_env("CODER_TF_BACKEND_AWS_PROFILE")
  CODER_TF_BACKEND_ENCRYPT         = get_env("CODER_TF_BACKEND_ENCRYPT")

  CODER_AWS_PROFILE = get_env("CODER_AWS_PROFILE")
  CODER_AWS_AZS     = get_env("CODER_AWS_AZS")

  CODER_CLUSTER_NAME          = get_env("CODER_CLUSTER_NAME")
  CODER_CLUSTER_VERSION       = get_env("CODER_CLUSTER_VERSION")
  CODER_CLUSTER_INSTANCE_TYPE = get_env("CODER_CLUSTER_INSTANCE_TYPE")
  CODER_VPC_NAME              = get_env("CODER_VPC_NAME")
  CODER_VPC_CIDR              = get_env("CODER_VPC_CIDR")
  CODER_VPC_AZS               = get_env("CODER_VPC_AZS")
  CODER_VPC_NAT_NAME          = get_env("CODER_VPC_NAT_NAME")
  CODER_DB_SUBNET_GROUP_NAME  = get_env("CODER_DB_SUBNET_GROUP_NAME")
  CODER_PUBLIC_SUBNET_SUFFIX  = get_env("CODER_PUBLIC_SUBNET_SUFFIX")
  CODER_PRIVATE_SUBNET_SUFFIX = get_env("CODER_PRIVATE_SUBNET_SUFFIX")

  CODER_IMAGE_REPO = get_env("CODER_IMAGE_REPO", "ghcr.io/coder/coder")
  CODER_IMAGE_TAG  = get_env("CODER_IMAGE_TAG", "v2.35.1")

  CODER_DB_RDS_ID   = get_env("CODER_DB_RDS_ID")
  CODER_DB_USERNAME = get_env("CODER_DB_USERNAME")
  CODER_DB_NAME     = get_env("CODER_DB_NAME")

  LOKI_S3_BUCKET_NAME   = get_env("LOKI_S3_BUCKET_NAME")
  LOKI_S3_BUCKET_REGION = get_env("LOKI_S3_BUCKET_REGION")

  GRAFANA_DOMAIN_NAME   = get_env("GRAFANA_DOMAIN_NAME")
  GRAFANA_DB_USERNAME   = get_env("GRAFANA_DB_USERNAME")
  GRAFANA_USER_PASSWORD = get_env("GRAFANA_USER_PASSWORD")

  CODER_DOMAIN_NAME  = get_env("CODER_DOMAIN_NAME")
  CODER_WILDCARD_URL = get_env("CODER_WILDCARD_URL")

  CODER_RUNNER_TOKEN = get_env("CODER_RUNNER_TOKEN")

  CF_EMAIL = get_env("CF_EMAIL")
  CF_TOKEN = get_env("CF_TOKEN")

  VANTAGE_API_TOKEN = get_env("VANTAGE_API_TOKEN")

  CODER_OIDC_ICON_URL      = get_env("CODER_OIDC_ICON_URL")
  CODER_OIDC_SCOPES        = get_env("CODER_OIDC_SCOPES")
  CODER_OIDC_EMAIL_DOMAIN  = get_env("CODER_OIDC_EMAIL_DOMAIN")
  CODER_OIDC_ISSUER_URL    = get_env("CODER_OIDC_ISSUER_URL")
  CODER_OIDC_CLIENT_ID     = get_env("CODER_OIDC_CLIENT_ID")
  CODER_OIDC_CLIENT_SECRET = get_env("CODER_OIDC_CLIENT_SECRET")

  CODER_GITHUB_OAUTH_CLIENT_ID           = get_env("CODER_GITHUB_OAUTH_CLIENT_ID")
  CODER_GITHUB_OAUTH_CLIENT_SECRET       = get_env("CODER_GITHUB_OAUTH_CLIENT_SECRET")
  CODER_GITHUB_EXTERN_AUTH_CLIENT_ID     = get_env("CODER_GITHUB_EXTERN_AUTH_CLIENT_ID")
  CODER_GITHUB_EXTERN_AUTH_CLIENT_SECRET = get_env("CODER_GITHUB_EXTERN_AUTH_CLIENT_SECRET")
}

generate "backend" {
  path      = "backend.tf"
  if_exists = "overwrite"

  contents = <<-EOF
    terraform {
      backend "s3" {}
    }
  EOF
}

remote_state {
  backend = "s3"
  config = {
    bucket  = "${local.CODER_TF_BACKEND_AWS_BUCKET_NAME}"
    region  = "${local.CODER_TF_BACKEND_AWS_REGION}"
    profile = "${local.CODER_TF_BACKEND_AWS_PROFILE}"
    encrypt = "${local.CODER_TF_BACKEND_ENCRYPT}"
    key     = "ai.coder.com/infra/${path_relative_to_include()}/terraform.tfstate"
  }
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
          version = "~> 6.52.0"
        }
        helm = {
          source  = "hashicorp/helm"
          version = "~> 3.1.1"
        }
        kubernetes = {
          source = "hashicorp/kubernetes"
          version = "~> 3.2.1"
        }
        grafana = {
          source = "grafana/grafana"
          version = "4.28.1"
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
          version = "~> 0.0.20"
        }
      }
    }
  EOF
}