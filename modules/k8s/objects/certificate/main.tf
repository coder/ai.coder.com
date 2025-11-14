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
  # Added validation because invalid issuer kind causes cert-manager errors
  validation {
    condition     = contains(["Issuer", "ClusterIssuer"], var.issuer_ref_kind)
    error_message = "issuer_ref_kind must be one of: Issuer, ClusterIssuer."
  }
}

variable "issuer_ref_name" {
  type = string
  # Added validation because empty issuer name causes cert-manager errors
  validation {
    condition     = var.issuer_ref_name != ""
    error_message = "issuer_ref_name must not be empty."
  }
}

variable "common_name" {
  type = string
}

variable "dns_names" {
  type = list(string)
}

output "manifest" {
  value = yamlencode({
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
  })
}