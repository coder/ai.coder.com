##
# Manifest Setup Post Addon-Deployment
# Includes auxiliary resources depending on CRDs
## 

##
# NodeClass + NodePool for Coder Server, Provisioner, & Workspaces
##

data "kubernetes_service_account_v1" "kptr" {
  metadata {
    name = "node-role"
    namespace = "karpenter"
  }
}

locals {
    nodeclass_configs = {
        "coder-server" = {
            user_data = ""
            block_device_mappings = []
        }
        "coder-workspace" = {
            user_data            = <<-EOF
                apiVersion: node.eks.aws/v1alpha1
                    kind: NodeConfig
                    spec:
                    kubelet:
                        config:
                        registryPullQPS: 30
            EOF
            block_device_mappings = [{
                deviceName = "/dev/xvda"
                ebs = {
                    volumeSize = "500Gi"
                    volumeType = "gp3"
                    encrypted = false
                    deleteOnTermination = true
                }
            }]
        }
        "coder-provisioner" = {
            user_data = ""
            block_device_mappings = []
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
        userData =  each.value.user_data
        }
    }
}

locals {
    nodepool_configs = {
        "coder-server" = {
            node_expires_after = "Never"
            disruption_consolidation_policy = "WhenEmpty"
            disruption_consolidate_after = "1m"
            taints = null
        }
        "coder-provisioner" = {
            node_expires_after = "Never"
            disruption_consolidation_policy = "WhenEmpty"
            disruption_consolidate_after = "1m"
            taints = null
        }
        "coder-workspace" = {
            node_expires_after = "Never"
            disruption_consolidation_policy = "WhenEmpty"
            disruption_consolidate_after = "30m"
            taints = null
        }
    }
}

resource "kubernetes_manifest" "nodepool" {

    depends_on = [ kubernetes_manifest.nodeclass ]

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
                      "node.coder.io/name"     = "coder"
                      "node.coder.io/part-of"  = "coder"
                      "node.coder.io/used-for" = each.key
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
                        },{
                        key      = "node.kubernetes.io/instance-type"
                        operator = "In"
                        values   = ["t3a.xlarge"]
                    }]
                    nodeClassRef = {
                        group = "karpenter.k8s.aws"
                        kind = "EC2NodeClass"
                        name = each.key
                    }
                    expireAfter = each.value.node_expires_after
                }
            }
            disruption = {
                consolidationPolicy = each.value.disruption_consolidation_policy
                consolidateAfter = each.value.disruption_consolidate_after
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
    kind = "StorageClass"
    metadata = {
      name = "default"
      annotations = {
        "storageclass.kubernetes.io/is-default-class" = "true"
      }
    }
    provisioner = "ebs.csi.eks.amazonaws.com"
    volumeBindingMode = "WaitForFirstConsumer"
    parameters = {
      type = "gp3"
      encrypted = "true"
    }
  }
}

##
# Cert-Manager ClusterIssuer for CA
##

data "kubernetes_service_account_v1" "r53" {
  metadata {
    name = "cert-manager-acme-dns01-route53"
    namespace = "cert-manager"
  }
}

resource "kubernetes_manifest" "default-issuer" {

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
            dns01 = {
              route53 = {
                region = var.region
                role = data.kubernetes_service_account_v1.r53.metadata[0].annotations["eks.amazonaws.com/role-arn"]
                auth = {
                  kubernetes = {
                    serviceAccountRef = {
                      name = data.kubernetes_service_account_v1.r53.metadata[0].name
                    }
                  }
                }
              }
            }
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
    name = "external-secrets"
    namespace = "external-secrets"
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
          region = var.region
          auth = {
            jwt = {
              serviceAccountRef = {
                name = data.kubernetes_service_account_v1.sm.metadata[0].name
                namespace = data.kubernetes_service_account_v1.sm.metadata[0].namespace
              } 
            }
          }
        }
      }
    }
  }
}