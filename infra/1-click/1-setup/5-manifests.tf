##
# Manifest Setup Post Addon-Deployment
# Includes auxiliary resources depending on CRDs
## 

##
# NodeClass + NodePool for Coder Server, Provisioner, & Workspaces
##

data "kubernetes_service_account_v1" "kptr" {
  metadata {
    name      = "node-role"
    namespace = "karpenter"
  }
}


locals {
  prefetch-script = templatefile("${path.module}/scripts/prefetch.sh.tftpl", {
    IMAGES = join(" ", ["docker.io/codercom/enterprise-base:ubuntu"])
    PRE_SCRIPT = ""
    POST_SCRIPT = ""
  })
  nodeclass_configs = {
    "coder" = {
      user_data = <<-EOF
        MIME-Version: 1.0
        Content-Type: multipart/mixed; boundary="//"

        --//
        Content-Type: application/node.eks.aws

        ${file("${path.module}/scripts/nodeconfig.yaml")}

        --//--
      EOF
      block_device_mappings = [{
        deviceName = "/dev/xvda"
        ebs = {
          volumeSize          = "500Gi"
          volumeType          = "gp3"
          encrypted           = false
          deleteOnTermination = true
        }
      }]
    }
  }
}

resource "kubernetes_manifest" "nodeclass" {

  for_each = local.nodeclass_configs

  manifest = {
    apiVersion = "karpenter.k8s.aws/v1"
    kind       = "EC2NodeClass"
    metadata = {
      name = each.key
    }
    spec = {
      role = data.kubernetes_service_account_v1.kptr.metadata[0].annotations["eks.amazonaws.com/role-arn"]
      amiSelectorTerms = [{
        alias = "al2023@latest"
      }]
      subnetSelectorTerms = [{
        tags = {
          "karpenter.sh/discovery" = "${var.name}-${local.normalized_domain_name}"
        }
      }]
      securityGroupSelectorTerms = [{
        tags = {
          "karpenter.sh/discovery" = "${var.name}-${local.normalized_domain_name}"
        }
      }]
      blockDeviceMappings = each.value.block_device_mappings
      userData            = each.value.user_data
    }
  }
}

locals {
  nodepool_configs = {
    "coder" = {
      node_expires_after              = "Never"
      disruption_consolidation_policy = "WhenEmpty"
      disruption_consolidate_after    = "1m"
      instance_type =                  "t3a.medium"
      taints                          = []
    }
  }
}

resource "kubernetes_manifest" "nodepool" {

  depends_on = [kubernetes_manifest.nodeclass]
  for_each = local.nodepool_configs

  field_manager {
    force_conflicts = true
  }

  wait {
    condition {
      type   = "Ready"
      status = "True"
    }
  }

  timeouts {
    create = "10m"
    update = "10m"
    delete = "30s"
  }

  manifest = {
    apiVersion = "karpenter.sh/v1"
    kind       = "NodePool"
    metadata = {
      name = each.key
    }
    spec = {
      template = {
        metadata = {
          labels = {
            "node.coder.io/instance"   = "coder-v2"
            "node.coder.io/managed-by" = "karpenter"
            "node.coder.io/name"       = "coder"
            "node.coder.io/part-of"    = "coder"
            "node.coder.io/used-for"   = each.key
          }
        }
        spec = {
          taints = each.value.taints == null ? [{
            key    = "dedicated"
            value  = each.key
            effect = "NoSchedule"
          }] : each.value.taints
          requirements = [{
            key      = "kubernetes.io/arch"
            operator = "In"
            values   = ["amd64"]
            }, {
            key      = "kubernetes.io/os"
            operator = "In"
            values   = ["linux"]
            }, {
            key      = "kubernetes.sh/capacity-type"
            operator = "In"
            values   = ["spot", "on-demand"]
            }, {
            key      = "node.kubernetes.io/instance-type"
            operator = "In"
            values   = [ each.value.instance_type ]
          }]
          nodeClassRef = {
            group = "karpenter.k8s.aws"
            kind  = "EC2NodeClass"
            name  = each.key
          }
          expireAfter = each.value.node_expires_after
        }
      }
      disruption = {
        consolidationPolicy = each.value.disruption_consolidation_policy
        consolidateAfter    = each.value.disruption_consolidate_after
      }
    }
  }
}

##
# Image Prefetch DaemonSet. Add images to warm new Coder nodes with workspace image.
##

resource "kubernetes_daemon_set_v1" "img-fetch" {

  depends_on = [kubernetes_manifest.nodepool]
  for_each = local.nodepool_configs

  metadata {
    name      = "imgs-for-${each.key}"
    namespace = "kube-system"
    labels = {
      "app.kubernetes.io/name"    = "img-fetch"
      "app.kubernetes.io/part-of" = "coder-workspaces"
    }
  }

  spec {
    selector {
      match_labels = {
        "app.kubernetes.io/name" = "img-fetch"
      }
    }

    template {
      metadata {
        labels = {
          "app.kubernetes.io/name" = "img-fetch"
        }
      }

      spec {
        node_selector = kubernetes_manifest.nodepool[each.key].manifest.spec.template.metadata.labels

        toleration {
          key      = "dedicated"
          value    = each.key
          effect   = "NoSchedule"
        }

        termination_grace_period_seconds = 5

        init_container {
          name    = "enterprise-base"
          image   = "docker.io/codercom/enterprise-base:ubuntu"
          command = []
        }

        container {
          name  = "pause"
          image = "registry.k8s.io/pause:3.9"

          resources {
            requests = {
              cpu    = "1m"
              memory = "1Mi"
            }
            limits = {
              cpu    = "10m"
              memory = "10Mi"
            }
          }
        }
      }
    }
  }
}

##
# EBS CSI Default StorageClass
##

resource "kubernetes_manifest" "default-sc" {
  manifest = {
    apiVersion = "storage.k8s.io/v1"
    kind       = "StorageClass"
    metadata = {
      name = "default"
      annotations = {
        "storageclass.kubernetes.io/is-default-class" = "true"
      }
    }
    provisioner       = "ebs.csi.aws.com"
    volumeBindingMode = "WaitForFirstConsumer"
    parameters = {
      type      = "gp3"
      encrypted = "true"
    }
  }
}

##
# Cert-Manager ClusterIssuer for CA
##

# If R53 enabled, then fetch service account from cert-manager for IAM Role
variable "r53_config" {
  description = "Enable to use Route53 as a DNS01 provider for ACME challenges."
  type = object({
    enabled = bool
  })
  default = {
    enabled     = true
  }
}

data "kubernetes_service_account_v1" "r53" {

  count = var.r53_config.enabled ? 1 : 0

  metadata {
    name = "crt-mgr"
    namespace = "cert-manager"
  }
}

# If CF enabled, then fetch secret from cert-manager for token
variable "cf_config" {
  description = "Enable to use CloudFlare as a DNS01 provider for ACME challenges."
  type = object({
    enabled = bool
    email = string
    name = optional(string, "cloudflare")
    namespace = optional(string, "cert-manager")
  })
  default = {
    enabled     = false
    email       = ""
    name = ""
    namespace = ""
  }
}

data "kubernetes_secret_v1" "cf" {

  count = var.cf_config.enabled ? 1 : 0

  metadata {
    name      = var.cf_config.name
    namespace = var.cf_config.namespace
  }
}

locals {
  dns01_r53 = ! var.r53_config.enabled ? null : {
    route53 = {
      region = var.region
      role   = data.kubernetes_service_account_v1.r53[0].metadata[0].annotations["eks.amazonaws.com/role-arn"]
      auth = {
        kubernetes = {
          serviceAccountRef = {
            name = data.kubernetes_service_account_v1.r53[0].metadata[0].name
          }
        }
      }
    }
  }
  dns01_cf = ! var.cf_config.enabled ? null : {
    cloudflare = {
      apiTokenSecretRef = {
        key  = data.kubernetes_secret_v1.cf[0].metadata[0].annotations["custom.kubernetes.secret/key"]
        name = data.kubernetes_secret_v1.cf[0].metadata[0].name
      }
      email = data.kubernetes_secret_v1.cf[0].metadata[0].annotations["custom.kubernetes.secret/email"]
    }
  }
}

resource "kubernetes_manifest" "issuer" {

  field_manager {
    force_conflicts = true
  }

  wait {
    condition {
      type   = "Ready"
      status = "True"
    }
  }

  timeouts {
    create = "10m"
    update = "10m"
    delete = "30s"
  }

  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind       = "ClusterIssuer"
    metadata = {
      labels = {}
      name   = "issuer"
    }
    spec = {
      acme = {
        privateKeySecretRef = {
          name = "issuer-account-key"
        }
        server = "https://acme-v02.api.letsencrypt.org/directory"
        solvers = [
          {
            dns01 = merge(
              local.dns01_r53, 
              local.dns01_cf
            )
          }
        ]
      }
    }
  }
}

##
# External-Secrets ClusterStore for syncing TLS/SSL
##

data "kubernetes_service_account_v1" "sm" {
  metadata {
    name      = "external-secrets"
    namespace = "ext-sec"
  }
}

resource "kubernetes_manifest" "secret-store" {

  field_manager {
    force_conflicts = true
  }

  wait {
    condition {
      type   = "Ready"
      status = "True"
    }
  }

  timeouts {
    create = "10m"
    update = "10m"
    delete = "30s"
  }

  manifest = {
    apiVersion = "external-secrets.io/v1"
    kind       = "ClusterSecretStore"
    metadata = {
      labels = {}
      name   = "issuer"
    }
    spec = {
      provider = {
        aws = {
          service = "SecretsManager"
          region  = var.region
          auth = {
            jwt = {
              serviceAccountRef = {
                name      = data.kubernetes_service_account_v1.sm.metadata[0].name
                namespace = data.kubernetes_service_account_v1.sm.metadata[0].namespace
              }
            }
          }
        }
      }
    }
  }
}