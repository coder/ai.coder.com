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

data "aws_caller_identity" "this" {}

data "aws_vpc" "this" {
  tags = {
    Name = var.vpc_name
  }
}

data "aws_subnets" "private" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.this.id]
  }

  tags = {
    Name = "*${var.private_subnet_suffix}*"
  }
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
    allowVolumeExpansion = true
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
    allowVolumeExpansion = true
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

data "kubernetes_service_account_v1" "auto" {
  metadata {
    name      = "auto-mode-node-role"
    namespace = "default"
  }
}

data "aws_iam_roles" "auto-mode" {
  name_regex = "${var.cluster_name}-eks-auto-*"
  path_prefix = "/${data.aws_region.this.region}/"
}

locals {
  nodeclass_configs = {
    "platform" = {
      api_version               = "eks.amazonaws.com/v1"
      kind                      = "NodeClass"
      subnet_selector           = [for subnet_id in data.aws_subnets.private.ids : { id = subnet_id }]
      sg_selector               = [{ id = data.aws_eks_cluster.this.vpc_config[0].cluster_security_group_id }]
      network_policy            = "DefaultAllow"
      network_policy_event_logs = "Disabled"
      snat_policy               = "Disabled"
      ephemeral_storage = {
        iops       = 3000
        size       = "80Gi"
        throughput = 125
      }
      role = data.kubernetes_service_account_v1.auto.metadata[0].annotations["eks.amazonaws.com/role-name"]
      tags = {
        Name = "platform-node"
      }
    }
    "coder-provisioner" = {
      api_version               = "eks.amazonaws.com/v1"
      kind                      = "NodeClass"
      subnet_selector           = [for subnet_id in data.aws_subnets.private.ids : { id = subnet_id }]
      sg_selector               = [{ id = data.aws_eks_cluster.this.vpc_config[0].cluster_security_group_id }]
      network_policy            = "DefaultAllow"
      network_policy_event_logs = "Disabled"
      snat_policy               = "Disabled"
      ephemeral_storage = {
        iops       = 3000
        size       = "80Gi"
        throughput = 125
      }
      role = data.kubernetes_service_account_v1.auto.metadata[0].annotations["eks.amazonaws.com/role-name"]
      tags = {
        Name = "coder-provisioner-node"
      }
    }   
    "coder-workspace" = {
      api_version        = "karpenter.k8s.aws/v1"
      kind               = "EC2NodeClass"
      user_data          = <<-EOT
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
      subnet_selector    = [for subnet_id in data.aws_subnets.private.ids : { id = subnet_id }]
      ami_selector = [{ alias = "al2023@latest" }]
      sg_selector        = [{ id = data.aws_eks_cluster.this.vpc_config[0].cluster_security_group_id }]
      block_device_mappings = [{
        deviceName = "/dev/xvda"
        ebs = {
          volumeSize          = "200Gi"
          volumeType          = "gp3"
          encrypted           = false
          deleteOnTermination = true
        }
      }]
      role = data.kubernetes_service_account_v1.kptr.metadata[0].annotations["eks.amazonaws.com/role-name"]
      tags = {
        Name = "coder-workspace-node"
      }
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
    spec = merge({
      role                       = each.value.role
      tags                       = try(each.value.tags, null)
      subnetSelectorTerms        = each.value.subnet_selector
      securityGroupSelectorTerms = each.value.sg_selector
    }, each.value.kind == "NodeClass" ? {
      networkPolicy              = each.value.network_policy
      networkPolicyEventLogs     = each.value.network_policy_event_logs
      snatPolicy                 = each.value.snat_policy
      ephemeralStorage           = each.value.ephemeral_storage
    } : null, each.value.kind == "EC2NodeClass" ? {
      amiSelectorTerms           = each.value.ami_selector
      blockDeviceMappings        = each.value.block_device_mappings
      userData                   = each.value.user_data
    }: null)
  }
}

##
# NodePool(s) for Coder (Server, Provisioner, & Workspaces)
##

locals {
  nodepool_configs = {
    # Grafana, Loki, AlertManager (Less resource intense)
    "observability-platform" = {
      disruption = {
        consolidation_policy = "WhenEmpty"
        consolidate_after    = "72h"
      }
      instance_types                  = ["c6g.large", "c6g.xlarge"]
      node_class_ref = {
        group = "eks.amazonaws.com"
        kind  = "NodeClass"
        name  = "platform"
      }
      taints = [{
        key    = "platform"
        value  = "observability-platform"
        effect = "NoSchedule"
      }]
    }
    "grafana" = {
      disruption = {
        consolidation_policy = "WhenEmpty"
        consolidate_after    = "72h"
      }
      instance_types                  = ["c6g.medium", "c6g.xlarge"]
      node_class_ref = {
        group = "eks.amazonaws.com"
        kind  = "NodeClass"
        name  = "platform"
      }
      taints = [{
        key    = "platform"
        value  = "grafana"
        effect = "NoSchedule"
      }]
    }
    "alertmanager" = {
      disruption = {
        consolidation_policy = "WhenEmpty"
        consolidate_after    = "72h"
      }
      instance_types                  = ["c6g.medium", "c6g.xlarge"]
      node_class_ref = {
        group = "eks.amazonaws.com"
        kind  = "NodeClass"
        name  = "platform"
      }
      taints = [{
        key    = "platform"
        value  = "alertmanager"
        effect = "NoSchedule"
      }]
    }
    "prometheus" = {
      disruption = {
        consolidation_policy = "WhenEmpty"
        consolidate_after    = "72h"
      }
      instance_types                  = ["c6g.2xlarge"]
      node_class_ref = {
        group = "eks.amazonaws.com"
        kind  = "NodeClass"
        name  = "platform"
      }
      taints = [{
        key    = "platform"
        value  = "prometheus"
        effect = "NoSchedule"
      }]
    }
    "loki" = {
      disruption = {
        consolidation_policy = "WhenEmpty"
        consolidate_after    = "72h"
      }
      instance_types                  = ["c6g.medium", "c6g.xlarge"]
      node_class_ref = {
        group = "eks.amazonaws.com"
        kind  = "NodeClass"
        name  = "platform"
      }
      taints = [{
        key    = "platform"
        value  = "loki"
        effect = "NoSchedule"
      }]
    }
    "litellm" = {
      disruption = {
        consolidation_policy = "WhenEmpty"
        consolidate_after    = "72h"
      }
      instance_types                  = ["c6g.xlarge"]
      node_class_ref = {
        group = "eks.amazonaws.com"
        kind  = "NodeClass"
        name  = "platform"
      }
      taints = [{
        key    = "platform"
        value  = "litellm"
        effect = "NoSchedule"
      }]
    }
    "coder-server" = {
      disruption = {
        consolidation_policy = "WhenEmpty"
        consolidate_after    = "72h"
      }
      instance_types                  = ["c6g.xlarge"]
      node_class_ref = {
        group = "eks.amazonaws.com"
        kind  = "NodeClass"
        name  = "platform"
      }
      taints = [{
        key    = "platform"
        value  = "coder-server"
        effect = "NoSchedule"
      }]
    }
    "coder-provisioner" = {
      disruption = {
        consolidation_policy = "WhenEmptyOrUnderutilized"
        consolidate_after    = "0s"
        budgets = [{
          nodes = "100%"
        }]
      }
      instance_types                  = ["c6a.xlarge"]
      node_class_ref = {
        group = "eks.amazonaws.com"
        kind  = "NodeClass"
        name  = "coder-provisioner"
      }
      taints = [{
        key    = "coder"
        value  = "provisioner"
        effect = "NoSchedule"
      }]
    }
    "coder-workspace" = {
      disruption = {
        consolidation_policy = "WhenEmpty"
        consolidate_after    = "0s"
        budgets = [{
          nodes = "100%"
        }]
      }
      instance_types = ["c6a.8xlarge"]
      node_class_ref = {
        group = "karpenter.k8s.aws"
        kind  = "EC2NodeClass"
        name  = "coder-workspace"
      }
      taints = []
    }
    "coder-workspace-static" = {
      disruption = {
        consolidation_policy = "WhenEmpty"
        consolidate_after    = "0s"
        budgets = [{
          nodes = "100%"
        }]
      }
      replicas                        = 2
      limits = {
        nodes = 100
      }
      instance_types = ["c6a.8xlarge"]
      node_class_ref = {
        group = "karpenter.k8s.aws"
        kind  = "EC2NodeClass"
        name  = "coder-workspace"
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
    spec = merge(try(each.value.replicas, null) == null ? {
      disruption = {
        consolidationPolicy = try(each.value.disruption.consolidation_policy, "WhenEmptyOrUnderutilized")
        consolidateAfter    = try(each.value.disruption.consolidate_after, "0s")
        budgets             = try(each.value.disruption.budgets, [{ nodes = "10%" }])
      }
    } : null, try(each.value.replicas, null) != null ? {
      replicas = each.value.replicas
    } : null, try(each.value.limits, null) != null ? {
      limits = each.value.limits
    } : null, {
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
          # https://docs.aws.amazon.com/eks/latest/userguide/automode.html#_features
          # 21 days (504 hours i.e. ExpireAfter + TerminationGracePeriod) maximum lifetime for AutoMode
          # https://karpenter.sh/docs/concepts/nodepools/
          # "Never" works for Karpenter though.
          expireAfter  = try(each.value.node_expires_after, each.value.node_class_ref != "karpenter.k8s.aws" ? "480h" : "Never")
          taints = each.value.taints == null ? [{
            key    = "dedicated"
            value  = each.key
            effect = "NoSchedule"
          }] : each.value.taints
          requirements = [{
            key      = "kubernetes.io/arch"
            operator = "In"
            values   = ["amd64", "arm64"]
            }, {
            key      = "kubernetes.io/os"
            operator = "In"
            values   = ["linux"]
            }, {
            key      = "karpenter.sh/capacity-type"
            operator = "In"
            values   = ["spot", "on-demand"]
            }, {
            key      = "node.kubernetes.io/instance-type"
            operator = "In"
            values   = each.value.instance_types
          }]
          nodeClassRef = each.value.node_class_ref
        }
      }
    })
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
    name      = "cloudflare-token"
    namespace = var.cloudflare_secret_namespace
    annotations = {
      "custom.kubernetes.secret/key"   = local.cf_secret_key
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

locals {
  prewarm_imgs = [
    "codercom/enterprise-java:latest",
    "codercom/enterprise-golang:latest",
    "codercom/enterprise-node:latest",
    "codercom/enterprise-base:ubuntu",
    "public.ecr.aws/f7a1d7a4/coder-aienv:1.1.2"
  ]
}

resource "kubernetes_daemon_set_v1" "img-fetch" {

  for_each = toset([
    "coder-workspace", 
    "coder-workspace-static"
  ])

  metadata {
    name      = "imgs-for-${each.key}"
    namespace = "default"
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

        dynamic "init_container" {
          for_each = toset(local.prewarm_imgs)
          content {
            name = replace(init_container.value, "/\\W/", "-")
            image   = init_container.value
            command = []
          }
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

locals {
  reg_mirror = "${data.aws_caller_identity.this.account_id}.dkr.ecr.${var.region}.amazonaws.com"
  reg_suffix = {
    "ghcr" = "ghcr.io"
    "k8s" = "registry.k8s.io"
    "quay" = "quay.io"
    "docker-hub" = "index.docker.io"
    "ecr-public" = "public.ecr.aws"
  }
}

resource "kubernetes_manifest" "mutate_img_policy" {
  manifest = {
    apiVersion = "policies.kyverno.io/v1"
    kind       = "MutatingPolicy"
    metadata = {
      name      = "mutate-ws-image"
    }
    spec = {
      matchConstraints = {
        matchPolicy = "Equivalent"
        namespaceSelector = {
          matchExpressions = [{
            key = "kubernetes.io/metadata.name"
            operator = "In"
            values = [
              "default", 
              "litellm", 
              "observability",
              "ebs-controller",
              "coder",
              "coder-ws-demo",
              "coder-ws-experiment",
              "coder-ws"
            ]
          }]
        }
        objectSelector = {
          matchExpressions = [
            {
              key = "app.kubernetes.io/name"
              operator = "NotIn"
              values = [
                # "coder-provisioner", 
                # "coder"
                "test"
              ]
            },
            {
              key = "app.kubernetes.io/managed-by"
              operator = "NotIn"
              values = [
                # "Helm",
                "test"
              ]
            }
          ]
        }
        resourceRules = [
          {
            apiGroups   = [""]
            apiVersions = ["v1"]
            operations  = ["CREATE", "UPDATE"]
            resources   = ["pods"]
          }
        ]
      }
      mutations = [ for k in ["containers", "initContainers", "ephemeralContainers"] : {
        patchType = "JSONPatch"
        jsonPatch = {
          expression = <<-EOT
            object.spec.?${k}.orValue([]).map(c, 
              %{ for suffix,reg in local.reg_suffix ~}
              image(c.image).registry() == "${reg}" ? 
              JSONPatch{
                op: "replace",
                path: "/spec/${k}/" + string(object.spec.?${k}.orValue([]).indexOf(c)) + "/image",
                value: "${local.reg_mirror}" + "/" + "${suffix}" + "/" + string(image(c.image).repository()) + ":" + string(image(c.image).tag())
              } :
              %{ endfor ~}
              null
            ).filter(p, p != null)
          EOT
        }
      } ]
    }
  }
}