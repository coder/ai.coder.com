terraform {}

variable "name" {
  type = string
}

variable "namespace" {
  type = string
}

variable "secret_name" {
  type = string
}

variable "issuer_ref_kind" {
  type    = string
  default = "ClusterIssuer"
}

variable "issuer_ref_name" {
  type = string
}

variable "common_name" {
  type = string
}

variable "dns_names" {
  type = list(string)
}

output "manifest" {
  value = {
    apiVersion = "cert-manager.io/v1"
    kind       = "Certificate"
    metadata = {
      name      = var.name
      namespace = var.namespace
    }
    spec = {
      secretName = var.secret_name
      issuerRef = {
        name = var.issuer_ref_name
        kind = var.issuer_ref_kind
      }
      commonName = var.common_name
      dnsNames   = var.dns_names
    }
  }
}