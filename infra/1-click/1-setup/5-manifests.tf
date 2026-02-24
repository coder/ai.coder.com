##
# Manifest Setup Post Addon-Deployment
# Includes auxiliary resources depending on CRDs
## 

##
# EBS CSI StorageClasses
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
    allowedTopologies = [{
      matchLabelExpressions = [{
        key    = "topology.ebs.csi.aws.com/zone"
        values = [for az in var.azs : "${data.aws_region.this.region}${az}"]
      }]
    }]
    parameters = {
      type      = "gp3"
      encrypted = "true"
    }
  }
}

resource "kubernetes_manifest" "automode-sc" {
  manifest = {
    apiVersion = "storage.k8s.io/v1"
    kind       = "StorageClass"
    metadata = {
      name = "automode"
    }
    provisioner       = "ebs.csi.eks.amazonaws.com"
    volumeBindingMode = "WaitForFirstConsumer"
    allowedTopologies = [{
      matchLabelExpressions = [{
        key    = "eks.amazonaws.com/compute-type"
        values = ["auto"]
      }]
    }]
    parameters = {
      type      = "gp3"
      encrypted = "true"
    }
  }
}

##
# NodeClass(es) for Coder (Server, Provisioner, & Workspaces)
##

data "kubernetes_service_account_v1" "kptr" {
  metadata {
    name      = "node-role"
    namespace = "karpenter"
  }
}

locals {
  nodeclass_configs = {
    "coder" = {
      api_version = "karpenter.k8s.aws/v1"
      kind        = "EC2NodeClass"
      user_data   = <<-EOT
        MIME-Version: 1.0
        Content-Type: multipart/mixed; boundary="//"

        --//
        Content-Type: application/node.eks.aws

        apiVersion: node.eks.aws/v1alpha1
        kind: NodeConfig
        spec:
          kubelet:
            config:
              registryPullQPS: 30
        
        --//--
      EOT
      subnet_selector = [{
        tags = {
          "karpenter.sh/discovery" = "${local.formatted_name}"
        }
      }]
      sg_selector = [{
        # Use for EKS AutoMode. AWS manages this, not TF: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_cluster#cluster_security_group_id-1
        id = data.aws_eks_cluster.coder.vpc_config[0].cluster_security_group_id
        # tags = {
        #   # If AutoMode is enabled, THIS BREAKS. Communication to CoreDNS locked behind system nodes. Kptr SG cant talk to AutoMode's SGs (only trusts itself and another AWS-managed SG)
        #   "karpenter.sh/discovery" = "${local.formatted_name}-karpenter"
        # }
      }]
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
    apiVersion = each.value.api_version
    kind       = each.value.kind
    metadata = {
      name = each.key
    }
    spec = {
      role = data.kubernetes_service_account_v1.kptr.metadata[0].annotations["eks.amazonaws.com/role-arn"]
      amiSelectorTerms = [{
        alias = "al2023@latest"
      }]
      subnetSelectorTerms        = each.value.subnet_selector
      securityGroupSelectorTerms = each.value.sg_selector
      blockDeviceMappings        = each.value.block_device_mappings
      userData                   = each.value.user_data
    }
  }
}

##
# NodePool(s) for Coder (Server, Provisioner, & Workspaces)
##

locals {
  nodepool_configs = {
    # "automode" = {
    #   node_expires_after              = "24h"
    #   disruption_consolidation_policy = "WhenEmpty"
    #   disruption_consolidate_after    = "1m"
    #   instance_type                   = "t3a.large"
    #   node_class_ref = {
    #     group = "eks.amazonaws.com"
    #     kind  = "NodeClass"
    #     name  = "default"
    #   }
    #   taints                          = []
    # }
    "karpenter" = {
      node_expires_after              = "24h"
      disruption_consolidation_policy = "WhenEmpty"
      disruption_consolidate_after    = "1m"
      instance_type                   = "t3a.large"
      node_class_ref = {
        group = "karpenter.k8s.aws"
        kind  = "EC2NodeClass"
        name  = "coder"
      }
      taints = []
    }
  }
}

resource "kubernetes_manifest" "nodepool" {

  depends_on = [kubernetes_manifest.nodeclass]
  for_each   = local.nodepool_configs

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
            # "eks.amazonaws.com/compute-type" = "auto"
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
            }, {
            key      = "node.kubernetes.io/instance-type"
            operator = "In"
            values   = [each.value.instance_type]
          }]
          nodeClassRef = each.value.node_class_ref
          expireAfter  = each.value.node_expires_after
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

        # Select's Coder-specific nodes. Do not pull on system nodes.
        node_selector = kubernetes_manifest.nodepool[each.key].manifest.spec.template.metadata.labels

        toleration {
          key    = "dedicated"
          value  = each.key
          effect = "NoSchedule"
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