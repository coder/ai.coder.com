locals {
  CODER_TF_BACKEND_AWS_BUCKET_NAME = get_env("CODER_TF_BACKEND_AWS_BUCKET_NAME")
  CODER_TF_BACKEND_AWS_REGION = get_env("CODER_TF_BACKEND_AWS_REGION", "us-east-2")
  CODER_TF_BACKEND_AWS_PROFILE = get_env("CODER_TF_BACKEND_AWS_PROFILE", "default")
  CODER_TF_BACKEND_ENCRYPT = get_env("CODER_TF_BACKEND_ENCRYPT", "false")

  CODER_AWS_PROFILE = get_env("CODER_AWS_PROFILE", "default")
  CODER_AWS_REGION = get_env("CODER_AWS_REGION", "us-east-2")
  CODER_AWS_AZS = get_env("CODER_AWS_AZS", jsonencode(["a", "c"]))

  CODER_CLUSTER_NAME = get_env("CODER_CLUSTER_NAME", "coder")
  CODER_CLUSTER_VERSION = get_env("CODER_CLUSTER_VERSION", "1.35")
  CODER_CLUSTER_INSTANCE_TYPE = get_env("CODER_CLUSTER_INSTANCE_TYPE", "c6a.large")
  CODER_VPC_NAME = get_env("CODER_VPC_NAME", "coder")
  CODER_VPC_CIDR = get_env("CODER_VPC_CIDR", "10.0.0.0/16")
  CODER_VPC_AZS = get_env("CODER_VPC_AZS", jsonencode(["a", "b", "c"]))
  CODER_VPC_NAT_NAME = get_env("CODER_VPC_NAT_NAME", "nat-instance")
  CODER_DB_SUBNET_GROUP_NAME = get_env("CODER_DB_SUBNET_GROUP_NAME", "coder-db-subnet-group")
  CODER_PUBLIC_SUBNET_SUFFIX = get_env("CODER_PUBLIC_SUBNET_SUFFIX", "public")
  CODER_PRIVATE_SUBNET_SUFFIX = get_env("CODER_PRIVATE_SUBNET_SUFFIX", "private")

  CODER_DB_RDS_ID = get_env("CODER_DB_RDS_ID", "coder")
  CODER_DB_USERNAME = get_env("CODER_DB_USERNAME", "coder")
  CODER_DB_PASSWORD = get_env("CODER_DB_PASSWORD", "th1s1sn0tas3cur3pass0wrd")
  CODER_DB_NAME = get_env("CODER_DB_NAME", "coder")
  
  LITELLM_DOMAIN_NAME = get_env("LITELLM_DOMAIN_NAME")
  LITELLM_ADDON_NAMESPACE = get_env("LITELLM_ADDON_NAMESPACE", "litellm")
  LITELLM_ADDON_VERSION = get_env("LITELLM_ADDON_VERSION", "0.1.830")
  LITELLM_DB_RDS_ID = get_env("LITELLM_DB_RDS_ID", "litellm")
  LITELLM_DB_NAME = get_env("LITELLM_DB_NAME", "litellm")
  LITELLM_DB_USERNAME = get_env("LITELLM_DB_USERNAME", "litellm")
  LITELLM_DB_USER_PASSWORD = get_env("LITELLM_DB_USER_PASSWORD", "th1s1sn0tas3cur3pass0wrd")
  LITELLM_DB_ADMIN_PASSWORD = get_env("LITELLM_DB_ADMIN_PASSWORD", "th1s1sn0tas3cur3pass0wrd")
  LITELLM_GCLOUD_AUTH = get_env("LITELLM_GCLOUD_AUTH", "th1s1sn0tas3cur3pass0wrd")
  LITELLM_MASTER_KEY = get_env("LITELLM_MASTER_KEY", "th1s1sn0tas3cur3pass0wrd")

  CODER_IMAGE_REPO = get_env("CODER_IMAGE_REPO", "ghcr.io/coder/coder")
  CODER_IMAGE_TAG = get_env("CODER_IMAGE_TAG", "v2.28.6")
  CODER_ADDON_VERSION = get_env("CODER_ADDON_VERSION", "2.25.1")
  CODER_LOGSTREAM_ADDON_VERSION = get_env("CODER_LOGSTREAM_ADDON_VERSION", "0.0.11")

  KPTR_ADDON_NAMESPACE = get_env("KPTR_ADDON_NAMESPACE", "karpenter")
  KPTR_ADDON_VERSION = get_env("KPTR_ADDON_VERSION", "1.9.0")

  CRTMGR_ADDON_VERSION = get_env("CRTMGR_ADDON_VERSION", "v1.18.2")
  CRTMGR_ADDON_NAMESPACE = get_env("CRTMGR_ADDON_NAMESPACE", "cert-manager")

  EBS_ADDON_NAMESPACE = get_env("EBS_ADDON_NAMESPACE", "ebs-controller")
  EBS_ADDON_VERSION = get_env("EBS_ADDON_VERSION", "2.22.1")
  EBS_ADDON_REPLACE = get_env("EBS_ADDON_REPLACE", "true")

  LB_ADDON_NAMESPACE = get_env("LB_ADDON_NAMESPACE", "lb-controller")
  LB_ADDON_VERSION = get_env("LB_ADDON_VERSION", "1.13.2")
  LB_ADDON_USE_CERTMGR = get_env("LB_ADDON_USE_CERTMGR", "true")

  METRICS_SRV_ADDON_NAMESPACE = get_env("METRICS_SRV_ADDON_NAMESPACE", "kube-system")
  METRICS_SRV_ADDON_VERSION = get_env("METRICS_SRV_ADDON_VERSION", "3.13.0")

  CODER_OBSRV_CHART_VERSION = get_env("CODER_OBSRV_CHART_VERSION", "0.7.0-rc.1")
  CODER_OBSRV_CHART_NAMESPACE = get_env("CODER_OBSRV_CHART_NAMESPACE", "observability")

  LOKI_S3_BUCKET_NAME = get_env("LOKI_S3_BUCKET_NAME", "loki")
  LOKI_S3_BUCKET_REGION = get_env("LOKI_S3_BUCKET_REGION", "us-east-2")

  GRAFANA_DOMAIN_NAME = get_env("GRAFANA_DOMAIN_NAME")

  GRAFANA_DB_RDS_ID = get_env("GRAFANA_DB_RDS_ID", "grafana")
  GRAFANA_DB_NAME = get_env("GRAFANA_DB_NAME", "grafana")
  GRAFANA_DB_USERNAME = get_env("GRAFANA_DB_USERNAME",  "grafana")
  GRAFANA_DB_PASSWORD = get_env("GRAFANA_DB_PASSWORD",  "Th1s1sN0TS3CuR3!!")

  GRAFANA_USERNAME = get_env("GRAFANA_USERNAME", "admin")
  GRAFANA_PASSWORD = get_env("GRAFANA_PASSWORD",  "Th1s1sN0TS3CuR3!!")

  GRAFANA_ADMIN_USERNAME = get_env("GRAFANA_ADMIN_USERNAME", "admin")
  GRAFANA_ADMIN_PASSWORD = get_env("GRAFANA_ADMIN_PASSWORD",  "Th1s1sN0TS3CuR3!!")

  CODER_DOMAIN_NAME = get_env("CODER_DOMAIN_NAME")
  CODER_WILDCARD_URL = get_env("CODER_WILDCARD_URL")
  CODER_LICENSE = get_env("CODER_LICENSE", "")
  CODER_EXPERIMENTS = get_env("CODER_EXPERIMENTS", jsonencode([]))
  CODER_BUILT_IN_PROVISIONER_COUNT = get_env("CODER_BUILT_IN_PROVISIONER_COUNT", "0")

  CODER_USERNAME = get_env("CODER_USERNAME", "admin")
  CODER_EMAIL = get_env("CODER_EMAIL", "admin@coder.com")
  CODER_PASSWORD = get_env("CODER_PASSWORD", "Th1s1sN0TS3CuR3!!")

  CF_EMAIL = get_env("CF_EMAIL")
  CF_TOKEN = get_env("CF_TOKEN")

  CODER_OIDC_SIGN_IN_TEXT = get_env("CODER_OIDC_SIGN_IN_TEXT")
  CODER_OIDC_ICON_URL = get_env("CODER_OIDC_ICON_URL")
  CODER_OIDC_SCOPES = get_env("CODER_OIDC_SCOPES", "[]")
  CODER_OIDC_EMAIL_DOMAIN = get_env("CODER_OIDC_EMAIL_DOMAIN")
  CODER_OIDC_ISSUER_URL = get_env("CODER_OIDC_ISSUER_URL")
  CODER_OIDC_CLIENT_ID = get_env("CODER_OIDC_CLIENT_ID")
  CODER_OIDC_CLIENT_SECRET = get_env("CODER_OIDC_CLIENT_SECRET")

  CODER_GITHUB_OAUTH_CLIENT_ID = get_env("CODER_GITHUB_OAUTH_CLIENT_ID")
  CODER_GITHUB_OAUTH_CLIENT_SECRET = get_env("CODER_GITHUB_OAUTH_CLIENT_SECRET")
  CODER_GITHUB_EXTERN_AUTH_CLIENT_ID = get_env("CODER_GITHUB_EXTERN_AUTH_CLIENT_ID")
  CODER_GITHUB_EXTERN_AUTH_CLIENT_SECRET = get_env("CODER_GITHUB_EXTERN_AUTH_CLIENT_SECRET")

  CODER_ANTHROPIC_LLM_ENDPOINT = get_env("CODER_ANTHROPIC_LLM_ENDPOINT")
  CODER_ANTHROPIC_LLM_KEY = get_env("CODER_ANTHROPIC_LLM_KEY")
  CODER_OPENAI_LLM_ENDPOINT = get_env("CODER_OPENAI_LLM_ENDPOINT")
  CODER_OPENAI_LLM_KEY = get_env("CODER_OPENAI_LLM_KEY")
}

generate "backend" {
  path      = "backend.tf"
  if_exists = "overwrite"

  contents = <<-EOF
    terraform {
      backend "s3" {
        bucket = "${local.CODER_TF_BACKEND_AWS_BUCKET_NAME}"
        key            = "ai.coder.com/infra/aws/${path_relative_to_include()}/terraform.tfstate"
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
          version = "~> 6.52.0"
        }
        helm = {
          source  = "hashicorp/helm"
          version = "~> 3.1.1"
        }
        kubernetes = {
          source = "hashicorp/kubernetes"
          version = "~> 3.0.1"
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
          version = "~> 0.0.12"
        }
        argocd = {
          source  = "argoproj-labs/argocd"
          version = "~> 7.15.3"
        }
      }
    }
  EOF
}