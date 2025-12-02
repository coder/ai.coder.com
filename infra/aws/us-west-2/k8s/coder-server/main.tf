terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "3.1.1"
    }
    kubernetes = {
      source = "hashicorp/kubernetes"
    }
    coderd = {
      source = "coder/coderd"
    }
    acme = {
      source = "vancluever/acme"
    }
    tls = {
      source = "hashicorp/tls"
    }
  }
  backend "s3" {}
}

variable "cluster_name" {
  type = string
}

variable "cluster_region" {
  type = string
}

variable "cluster_profile" {
  type    = string
  default = "default"
}

variable "cluster_oidc_provider_arn" {
  type = string
}

variable "acme_server_url" {
  type    = string
  default = "https://acme-v02.api.letsencrypt.org/directory"
}

variable "acme_registration_email" {
  type = string
}

variable "addon_version" {
  type    = string
  default = "2.25.1"
}

variable "coder_access_url" {
  type = string
}

variable "coder_wildcard_access_url" {
  type = string
}

variable "coder_experiments" {
  type    = list(string)
  default = []
}

variable "coder_github_allowed_orgs" {
  type    = list(string)
  default = []
}

variable "coder_builtin_provisioner_count" {
  type    = number
  default = 0
}

variable "coder_github_external_auth_secret_client_secret" {
  type      = string
  sensitive = true
}

variable "coder_github_external_auth_secret_client_id" {
  type      = string
  sensitive = true
}

variable "coder_oauth_secret_client_secret" {
  type      = string
  sensitive = true
}

variable "coder_oauth_secret_client_id" {
  type      = string
  sensitive = true
}

variable "coder_oidc_secret_client_secret" {
  type      = string
  sensitive = true
}

variable "coder_oidc_secret_client_id" {
  type      = string
  sensitive = true
}

variable "coder_oidc_secret_issuer_url" {
  type      = string
  sensitive = true
}

variable "coder_db_secret_url" {
  type      = string
  sensitive = true
}

variable "coder_token" {
  type      = string
  sensitive = true
}

variable "image_repo" {
  type      = string
  sensitive = true
}

variable "image_tag" {
  type    = string
  default = "latest"
}

variable "kubernetes_ssl_secret_name" {
  type = string
}

variable "kubernetes_create_ssl_secret" {
  type    = bool
  default = true
}

variable "oidc_sign_in_text" {
  type = string
}

variable "oidc_icon_url" {
  type = string
}

variable "oidc_scopes" {
  type = list(string)
}

variable "oidc_email_domain" {
  type = string
}

provider "aws" {
  region  = var.cluster_region
  profile = var.cluster_profile
}

data "aws_eks_cluster" "this" {
  name = var.cluster_name
}

data "aws_eks_cluster_auth" "this" {
  name = var.cluster_name
}

provider "helm" {
  kubernetes = {
    host                   = data.aws_eks_cluster.this.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)
    token                  = data.aws_eks_cluster_auth.this.token
  }
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.this.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.this.token
}

provider "coderd" {
  url   = var.coder_access_url
  token = var.coder_token
}

provider "acme" {
  server_url = var.acme_server_url
}

# Fetch ACM certificate dynamically by domain to avoid hardcoding sensitive ARNs
data "aws_acm_certificate" "coder" {
  domain      = trimsuffix(trimprefix(var.coder_access_url, "https://"), "/")
  statuses    = ["ISSUED"]
  most_recent = true
}

module "coder-server" {
  source = "../../../../../modules/k8s/bootstrap/coder-server"

  cluster_name              = var.cluster_name
  cluster_oidc_provider_arn = var.cluster_oidc_provider_arn


  namespace                       = "coder"
  acme_registration_email         = var.acme_registration_email
  acme_days_until_renewal         = 90
  replica_count                   = 1 # HA requires Enterprise license
  helm_version                    = var.addon_version
  image_repo                      = var.image_repo
  image_tag                       = var.image_tag
  primary_access_url              = var.coder_access_url
  wildcard_access_url             = var.coder_wildcard_access_url
  coder_experiments               = var.coder_experiments
  coder_builtin_provisioner_count = var.coder_builtin_provisioner_count
  coder_github_allowed_orgs       = var.coder_github_allowed_orgs
  ssl_cert_config = {
    name          = var.kubernetes_ssl_secret_name
    create_secret = var.kubernetes_create_ssl_secret
  }
  oidc_config = {
    sign_in_text = var.oidc_sign_in_text
    icon_url     = var.oidc_icon_url
    scopes       = var.oidc_scopes
    email_domain = var.oidc_email_domain
  }
  db_secret_url                             = var.coder_db_secret_url
  oidc_secret_issuer_url                    = var.coder_oidc_secret_issuer_url
  oidc_secret_client_id                     = var.coder_oidc_secret_client_id
  oidc_secret_client_secret                 = var.coder_oidc_secret_client_secret
  oauth_secret_client_id                    = var.coder_oauth_secret_client_id
  oauth_secret_client_secret                = var.coder_oauth_secret_client_secret
  github_external_auth_secret_client_id     = var.coder_github_external_auth_secret_client_id
  github_external_auth_secret_client_secret = var.coder_github_external_auth_secret_client_secret
  tags                                      = {}
  env_vars = {
    # Disable redirect since NLB terminates TLS and forwards plain HTTP to backend
    # Without this, Coder sees HTTP and redirects to HTTPS, causing infinite redirect loop
    CODER_REDIRECT_TO_ACCESS_URL = "false"
    # Disable TLS on Coder itself since NLB terminates TLS
    CODER_TLS_ENABLE = "false"
    # Mark auth cookies as secure since users access via HTTPS
    CODER_SECURE_AUTH_COOKIE = "true"
    # Enable DERP server for multi-region replica communication
    CODER_DERP_SERVER_ENABLE = "true"
  }
  service_annotations = {
    "service.beta.kubernetes.io/aws-load-balancer-nlb-target-type"  = "instance"
    "service.beta.kubernetes.io/aws-load-balancer-scheme"           = "internet-facing"
    "service.beta.kubernetes.io/aws-load-balancer-attributes"       = "deletion_protection.enabled=false,load_balancing.cross_zone.enabled=true"
    "service.beta.kubernetes.io/aws-load-balancer-ssl-cert"         = data.aws_acm_certificate.coder.arn
    "service.beta.kubernetes.io/aws-load-balancer-ssl-ports"        = "443"
    "service.beta.kubernetes.io/aws-load-balancer-backend-protocol" = "tcp"
    # Subnets will be auto-detected by Load Balancer Controller using kubernetes.io/role/elb=1 tag
  }
  node_selector = {
    "node.coder.io/managed-by" = "karpenter"
    "node.coder.io/used-for"   = "coder-server"
  }
  tolerations = [{
    key      = "dedicated"
    operator = "Equal"
    value    = "coder-server"
    effect   = "NoSchedule"
  }]
  topology_spread_constraints = [{
    max_skew           = 1
    topology_key       = "kubernetes.io/hostname"
    when_unsatisfiable = "ScheduleAnyway"
    label_selector = {
      match_labels = {
        "app.kubernetes.io/name"    = "coder"
        "app.kubernetes.io/part-of" = "coder"
      }
    }
    match_label_keys = [
      "app.kubernetes.io/instance"
    ]
  }]
  pod_anti_affinity_preferred_during_scheduling_ignored_during_execution = [{
    weight = 100
    pod_affinity_term = {
      label_selector = {
        match_labels = {
          "app.kubernetes.io/instance" = "coder-v2"
          "app.kubernetes.io/name"     = "coder"
          "app.kubernetes.io/part-of"  = "coder"
        }
      }
      topology_key = "kubernetes.io/hostname"
    }
  }]
}

# Fix service HTTPS port to forward to HTTP backend (port 8080)
# since Coder has TLS disabled and only listens on HTTP
resource "null_resource" "patch_coder_service" {
  depends_on = [module.coder-server]

  triggers = {
    # Re-run patch whenever Coder configuration changes
    always_run = timestamp()
  }

  provisioner "local-exec" {
    command = <<-EOT
      sleep 10
      kubectl patch svc coder -n coder --type='json' \
        -p='[{"op": "replace", "path": "/spec/ports/1/targetPort", "value": "http"}]' \
        2>/dev/null || true
    EOT
  }
}
