terraform {}

variable "name" {
  type = string
}

variable "namespace" {
  type = string
}

variable "labels" {
  type    = map(string)
  default = {}
}

variable "annotations" {
  type    = map(string)
  default = {}
}

variable "replicas" {
  type    = number
  default = 0
}

variable "selector" {
  type    = map(string)
  default = {}
}

variable "template_labels" {
  type    = map(string)
  default = {}
}

variable "template_annotations" {
  type    = map(string)
  default = {}
}

variable "strategy" {
  type    = string
  default = "RollingUpdate"
}

variable "service_account_name" {
  type    = string
  default = ""
}

variable "containers" {
  type = list(object({
    name  = string
    image = string
    ports = list(object({
      name           = string
      container_port = number
      protocol       = string
    }))
    env = optional(map(string), {})
    env_secret = optional(map(object({
      key  = string
      name = optional(string)
    })), {})
    resources = object({
      requests = map(string)
      limits   = map(string)
    })
    command = optional(list(string), [])
    volume_mounts = optional(list(object({
      name       = string
      mount_path = string
      read_only  = optional(bool, false)
      sub_path   = optional(string, "")
    })), [])
  }))
  default = []
}

variable "volumes_from_secrets" {
  type    = list(string)
  default = []
}

variable "volumes_from_config_map" {
  type    = list(string)
  default = []
}

output "manifest" {
  value = yamlencode({
    apiVersion = "apps/v1"
    kind       = "Deployment"
    metadata = {
      name        = var.name
      namespace   = var.namespace
      labels      = var.labels
      annotations = var.annotations
    }
    spec = {
      replicas = var.replicas
      selector = {
        matchLabels = var.selector
      }
      template = {
        metadata = {
          labels      = var.template_labels
          annotations = var.template_annotations
        }
        spec = {
          serviceAccountName = var.service_account_name
          containers = [
            for c in var.containers : merge({
              name  = c.name
              image = c.image
              ports = [for v in c.ports : {
                name          = v.name
                containerPort = v.container_port
                protocol      = v.protocol
              }]
              env = concat([for k, v in c.env : {
                name  = k
                value = v
                }], [for k, v in c.env_secret : {
                name = k
                valueFrom = {
                  secretKeyRef = {
                    name = v.name
                    key  = v.key
                  }
                }
              }])
              resources = c.resources
              volumeMounts = [
                for m in c.volume_mounts : {
                  name      = m.name
                  mountPath = m.mount_path
                  readOnly  = m.read_only
                  subPath   = m.sub_path
                }
              ]
              # Only include command if not empty to avoid overriding container default
            }, length(c.command) > 0 ? { command = c.command } : {})
          ]
          volumes = concat([
            for v in var.volumes_from_config_map : {
              name      = v
              configMap = { name = v }
            }], [
            for v in var.volumes_from_secrets : {
              name   = v
              secret = { secretName = v }
            }
          ])
        }
      }
      strategy = {
        type = var.strategy
      }
    }
  })
}
