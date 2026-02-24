provider "aws" {
  region  = var.region
  profile = var.profile
}

data "aws_eks_cluster" "this" {
  name = var.cluster_name
}

data "aws_eks_cluster_auth" "this" {
  name = var.cluster_name
}

data "aws_iam_openid_connect_provider" "this" {
  url = data.aws_eks_cluster.this.identity[0].oidc[0].issuer
}

data "aws_region" "this" {}

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

##
# Manifest Setup Post Addon-Deployment
# Includes auxiliary resources depending on CRDs
## 

##
# EBS CSI StorageClasses
##

resource "kubernetes_manifest" "gp3" {
  manifest = {
    apiVersion = "storage.k8s.io/v1"
    kind       = "StorageClass"
    metadata = {
      name = "gp3"
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

resource "kubernetes_manifest" "automode-gp3" {
  manifest = {
    apiVersion = "storage.k8s.io/v1"
    kind       = "StorageClass"
    metadata = {
      name = "gp3-automode"
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
          "karpenter.sh/discovery" = "${var.cluster_name}"
        }
      }]
      sg_selector = [{
        # Use for EKS AutoMode. AWS manages this, not TF: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_cluster#cluster_security_group_id-1
        id = data.aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
        # tags = {
        #   # If AutoMode is enabled, THIS BREAKS. Communication to CoreDNS locked behind system nodes. Kptr SG cant talk to AutoMode's SGs (only trusts itself and another AWS-managed SG)
        #   "karpenter.sh/discovery" = "${var.cluster_name}"
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
    "karpenter" = {
      node_expires_after              = "24h"
      disruption_consolidation_policy = "WhenEmptyOrUnderutilized"
      disruption_consolidate_after    = "1m"
      instance_types                   = ["t3a.large"]
      node_class_ref = {
        group = "karpenter.k8s.aws"
        kind  = "EC2NodeClass"
        name  = "coder"
      }
      # Have non Coder workspace apps get allocated to this nodepool 
      taints = [{
        key = "dedicated"
        value = "general"
        effect = "NoSchedule"
      }]
    }
    "coder-workspace" = {
      node_expires_after              = "24h"
      disruption_consolidation_policy = "WhenEmptyOrUnderutilized"
      disruption_consolidate_after    = "1m"
      instance_types                   = ["c8i.xlarge","c8i.2xlarge","c8i.4xlarge"]
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

  depends_on = [ kubernetes_manifest.nodeclass ]
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
            values   = each.value.instance_types
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
# Setup Cert-Manager ClusterIssuer
##

locals {
  cf_secret_key = "key"
}

resource "kubernetes_secret_v1" "cf" {
  metadata {
    name = "cloudflare-token"
    namespace = var.cloudflare_secret_namespace
    annotations = {
      "custom.kubernetes.secret/key" = local.cf_secret_key
      "custom.kubernetes.secret/email" = var.cloudflare_email
    }
  }
  data = {
    (local.cf_secret_key) = var.cloudflare_api_token
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
      name   = var.cluster_issuer_name
    }
    spec = {
      acme = {
        privateKeySecretRef = {
          name = var.cluster_issuer_priv_key_ref
        }
        server = "https://acme-v02.api.letsencrypt.org/directory"
        solvers = [
          {
            dns01 = {
              cloudflare = {
                apiTokenSecretRef = {
                  key  = kubernetes_secret_v1.cf.metadata[0].annotations["custom.kubernetes.secret/key"]
                  name = kubernetes_secret_v1.cf.metadata[0].name
                }
                email = kubernetes_secret_v1.cf.metadata[0].annotations["custom.kubernetes.secret/email"]
              }
            }
          }
        ]
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