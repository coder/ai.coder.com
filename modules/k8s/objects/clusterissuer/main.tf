terraform {}

variable "name" {
  type = string
}

variable "namespace" {
  type = string
}

variable "private_key_secret_ref" {
  type = string
}

variable "acme_server" {
  type    = string
  default = "https://acme-v02.api.letsencrypt.org/directory"
}

variable "solvers" {
  # Simplified type from list(map(object)) to list(object) for better error handling
  type = list(object({
    cloudflare = optional(object({
      email = string
      api_token_secret_ref = object({
        name = string
        key  = string
      })
    }))
  }))
  default = []
}

locals {
  # Filter out null cloudflare values and only include valid solver configurations
  solvers = [for v in var.solvers : {
    cloudflare = v.cloudflare != null ? {
      email                = v.cloudflare.email
      api_token_secret_ref = v.cloudflare.api_token_secret_ref
    } : null
  } if v.cloudflare != null]
}

output "manifest" {
  value = yamlencode({
    apiVersion = "cert-manager.io/v1"
    kind       = "ClusterIssuer"
    metadata = {
      # ClusterIssuer is cluster-scoped and does not have a namespace
      name = var.name
    }
    spec = {
      acme = {
        privateKeySecretRef = {
          name = var.private_key_secret_ref
        }
        server  = var.acme_server
        solvers = local.solvers
      }
    }
  })
}