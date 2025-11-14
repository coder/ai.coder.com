terraform {
  required_providers {
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
    null = {
      source = "hashicorp/null"
    }
  }
}

variable "dns_names" {
  type = list(string)
  validation {
    condition     = length(var.dns_names) > 0
    error_message = "DNS names list must not be empty"
  }
}

variable "common_name" {
  type = string
  validation {
    condition     = length(var.common_name) > 0
    error_message = "Common name must not be empty"
  }
}

variable "acme_registration_email" {
  type = string
  validation {
    condition     = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.acme_registration_email))
    error_message = "ACME registration email must be a valid email address"
  }
}

variable "acme_days_until_renewal" {
  type    = number
  default = 30
}

variable "acme_revoke_certificate" {
  type    = bool
  default = true
}

variable "cloudflare_api_token" {
  type      = string
  sensitive = true
  validation {
    condition     = length(var.cloudflare_api_token) > 0
    error_message = "Cloudflare API token must not be empty"
  }
}

variable "kubernetes_secret_name" {
  type = string
  validation {
    condition     = length(var.kubernetes_secret_name) > 0
    error_message = "Kubernetes secret name must not be empty"
  }
}

variable "kubernetes_namespace" {
  type    = string
  default = "default"
}

resource "null_resource" "registration-email" {
  triggers = {
    registration_email = var.acme_registration_email
  }
}

resource "acme_registration" "this" {
  email_address = var.acme_registration_email

  lifecycle {
    replace_triggered_by = [null_resource.registration-email]
  }
}

resource "tls_private_key" "this" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "tls_cert_request" "this" {
  private_key_pem = tls_private_key.this.private_key_pem
  dns_names       = var.dns_names
  subject {
    common_name = var.common_name
  }
}

resource "acme_certificate" "this" {
  account_key_pem               = acme_registration.this.account_key_pem
  certificate_request_pem       = tls_cert_request.this.cert_request_pem
  min_days_remaining            = var.acme_days_until_renewal
  revoke_certificate_on_destroy = var.acme_revoke_certificate
  revoke_certificate_reason     = "cessation-of-operation"
  dns_challenge {
    provider = "cloudflare"
    config = {
      CF_DNS_API_TOKEN = var.cloudflare_api_token
    }
  }
}

locals {
  full_chain = "${acme_certificate.this.certificate_pem}${acme_certificate.this.issuer_pem}"
}

resource "kubernetes_secret" "coder-proxy-tls" {
  metadata {
    name      = var.kubernetes_secret_name
    namespace = var.kubernetes_namespace
  }
  data = {
    "tls.key" = tls_private_key.this.private_key_pem
    "tls.crt" = local.full_chain
  }
  type = "kubernetes.io/tls"

  # Ensure certificate is generated before creating secret
  depends_on = [acme_certificate.this]

  lifecycle {
    # Recreate secret when certificate changes
    create_before_destroy = true
  }
}

output "private_key_pem" {
  value     = tls_private_key.this.private_key_pem
  sensitive = true
}

output "full_chain_certificate_pem" {
  value     = local.full_chain
  sensitive = true
}

output "kubernetes_secret_name" {
  value = kubernetes_secret.coder-proxy-tls.metadata[0].name
}