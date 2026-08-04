# Manual Trigger - 1

provider "aws" {
  region  = var.region
  profile = var.profile
}

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

data "aws_eks_cluster" "this" {
  name = var.cluster_name
}

data "aws_eks_cluster_auth" "this" {
  name = var.cluster_name
}

data "aws_iam_openid_connect_provider" "this" {
  url = data.aws_eks_cluster.this.identity[0].oidc[0].issuer
}

data "aws_caller_identity" "me" {}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.this.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.this.token
}

locals {
  std_karpenter_format = "kptr"
  karpenter_queue_name = "${var.cluster_name}-kptr"
  # karpenter_queue_rule_name        = "${var.cluster_name}-kptr"
  karpenter_controller_role_name   = "${local.std_karpenter_format}-ctrl"
  karpenter_controller_policy_name = local.std_karpenter_format
  karpenter_node_role_name         = "${local.std_karpenter_format}-node"
}

locals {
  cluster_oidc_provider = trimprefix(data.aws_iam_openid_connect_provider.this.url, "https://")
  common_labels = {
    "node.coder.io/instance"   = "coder-v2"
    "node.coder.io/managed-by" = "karpenter"
    "node.coder.io/name"       = "coder"
    "node.coder.io/part-of"    = "coder"
  }
  common_node_requirements = [
    {
      key      = "kubernetes.io/arch"
      operator = "In"
      values   = ["amd64", "arm64"]
    },
    {
      key      = "kubernetes.io/os"
      operator = "In"
      values   = ["linux"]
    },
    {
      key      = "karpenter.sh/capacity-type"
      operator = "In"
      values   = ["spot", "on-demand"]
    }
  ]
}

module "karpenter" {
  source  = "terraform-aws-modules/eks/aws//modules/karpenter"
  version = "21.14.0"

  cluster_name     = var.cluster_name
  queue_name       = local.karpenter_queue_name
  rule_name_prefix = ""

  # Karpenter Controller Role
  create_iam_role          = true
  iam_role_name            = local.karpenter_controller_role_name
  iam_role_use_name_prefix = true
  iam_role_path            = "/${var.cluster_name}/${var.region}/"
  iam_role_policies = {
    AmazonEFSCSIDriverPolicy = "arn:aws:iam::aws:policy/service-role/AmazonEFSCSIDriverPolicy"
  }
  iam_role_source_assume_policy_documents = [
    data.aws_iam_policy_document.kptr_ctrl_assume_role_policy.json,
  ]

  # Karpenter Controller Policies
  iam_policy_use_name_prefix = true
  iam_policy_name            = local.karpenter_controller_policy_name
  iam_policy_statements = [{
    effect    = "Allow",
    actions   = toset(["iam:PassRole"]),
    resources = toset(["*"]),
  }]

  # Karpenter Node Role
  create_node_iam_role          = true
  node_iam_role_name            = local.karpenter_node_role_name
  node_iam_role_use_name_prefix = true
  node_iam_role_path            = "/${var.cluster_name}/${var.region}/"
  node_iam_role_additional_policies = {
    AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
    STSAssumeRole                = aws_iam_policy.sts.arn
    ECRMirrorPolicy              = aws_iam_policy.ecr-mirror.arn
  }

  create_pod_identity_association = false
  enable_spot_termination         = true
}

resource "kubernetes_manifest" "karpenter" {

  wait {
    fields = {
      "status.health.status" = "Healthy"
      "status.sync.status"   = "Synced"
    }
  }

  timeouts {
    create = "5m"
    update = "5m"
    delete = "30s"
  }

  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name        = "${var.region}.karpenter"
      namespace   = "argocd"
      labels      = {}
      annotations = {}
    }
    spec = {
      project = "default"
      source = {
        repoURL        = "https://github.com/coder/ai.coder.com"
        path           = "charts/karpenter"
        targetRevision = "main"
        helm = {
          releaseName = "karpenter"
          values = yamlencode({
            extra = {
              sa = {
                controller = {
                  annotations = {
                    "eks.amazonaws.com/role-arn"  = module.karpenter.iam_role_arn
                    "eks.amazonaws.com/role-name" = module.karpenter.iam_role_name
                  }
                }
                node = {
                  annotations = {
                    "eks.amazonaws.com/role-arn"  = module.karpenter.node_iam_role_arn
                    "eks.amazonaws.com/role-name" = module.karpenter.node_iam_role_name
                  }
                }
              }
            }
            karpenter = {
              enabled = true
              controller = {
                resources = {
                  limits   = null
                  requests = null
                }
              }
              dnsPolicy    = "ClusterFirst"
              nodeSelector = {}
              replicas     = 2
              podAnnotations = {
                "checksum/config" = sha256(join(",", [
                  jsonencode(module.karpenter.iam_role_arn),
                  jsonencode(module.karpenter.node_iam_role_arn)
                ]))
              }
              serviceAccount = {
                annotations = {
                  "eks.amazonaws.com/role-arn" = module.karpenter.iam_role_arn
                }
              }
              tolerations = [{
                key      = "CriticalAddonsOnly"
                operator = "Exists"
              }]
              topologySpreadConstraints = []
              affinity = {
                nodeAffinity = {
                  requiredDuringSchedulingIgnoredDuringExecution = {
                    nodeSelectorTerms = [{
                      matchExpressions = [
                        {
                          key      = "eks.amazonaws.com/compute-type",
                          operator = "In",
                          values   = ["auto"]
                        }
                      ]
                    }]
                  }
                }
                podAntiAffinity = {
                  preferredDuringSchedulingIgnoredDuringExecution = [{
                    weight = 100
                    podAffinityTerm = {
                      labelSelector = {
                        matchExpressions = [{
                          key      = "app.kubernetes.io/name"
                          operator = "In"
                          values   = ["karpenter"]
                        }]
                      }
                      topologyKey = "kubernetes.io/hostname"
                    }
                  }]
                }
              }
              settings = {
                clusterName = var.cluster_name
                featureGates = {
                  spotToSpotConsolidation = true
                  staticCapacity          = true
                }
                interruptionQueue = module.karpenter.queue_name
              }
            }
            nodeClasses = [
              {
                name                   = "platform"
                apiVersion             = "eks.amazonaws.com/v1"
                kind                   = "NodeClass"
                subnetSelectorTerms    = [for subnet_id in data.aws_subnets.private.ids : { id = subnet_id }]
                sgSelectorTerms        = [{ id = data.aws_eks_cluster.this.vpc_config[0].cluster_security_group_id }]
                networkPolicy          = "DefaultAllow"
                networkPolicyEventLogs = "Disabled"
                snatPolicy             = "Disabled"
                ephemeralStorage = {
                  iops       = 3000
                  size       = "80Gi"
                  throughput = 125
                }
                role = var.cluster_node_iam_role_name
                tags = {
                  Name = "platform-node"
                }
              },
              {
                name                   = "coder-provisioner"
                apiVersion             = "eks.amazonaws.com/v1"
                kind                   = "NodeClass"
                subnetSelectorTerms    = [for subnet_id in data.aws_subnets.private.ids : { id = subnet_id }]
                sgSelectorTerms        = [{ id = data.aws_eks_cluster.this.vpc_config[0].cluster_security_group_id }]
                networkPolicy          = "DefaultAllow"
                networkPolicyEventLogs = "Disabled"
                snatPolicy             = "Disabled"
                ephemeralStorage = {
                  iops       = 3000
                  size       = "80Gi"
                  throughput = 125
                }
                role = var.cluster_node_iam_role_name
                tags = {
                  Name = "coder-provisioner-node"
                }
              },
              {
                name                = "coder-workspace"
                apiVersion          = "karpenter.k8s.aws/v1"
                kind                = "EC2NodeClass"
                userData            = <<-EOT
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
                subnetSelectorTerms = [for subnet_id in data.aws_subnets.private.ids : { id = subnet_id }]
                amiSelectorTerms    = [{ alias = "al2023@latest" }]
                sgSelector          = [{ id = data.aws_eks_cluster.this.vpc_config[0].cluster_security_group_id }]
                blockDeviceMappings = [{
                  deviceName = "/dev/xvda"
                  ebs = {
                    volumeSize          = "200Gi"
                    volumeType          = "gp3"
                    encrypted           = false
                    deleteOnTermination = true
                  }
                }]
                role = module.karpenter.node_iam_role_name
                tags = {
                  Name = "coder-workspace-node"
                }
              }
            ]
            nodePools = [
              {
                name                = "system"
                consolidationPolicy = "WhenEmptyOrUnderutilized"
                consolidateAfter    = "72h"
                budgets             = [{ nodes = "10%" }]
                labels = merge(local.common_labels, {
                  "node.coder.io/used-for" = "system"
                })
                expireAfter = "480h"
                taints = [{
                  key    = "CriticalAddonsOnly"
                  value  = "true"
                  effect = "NoSchedule"
                }]
                requirements = concat(local.common_node_requirements, [{
                  key      = "node.kubernetes.io/instance-type"
                  operator = "In"
                  values   = ["c6g.large", "c6g.xlarge", "c6g.2xlarge"]
                }])
                nodeClassRef = {
                  group = "eks.amazonaws.com"
                  kind  = "NodeClass"
                  name  = "platform"
                }
              },
              {
                name                = "observability-platform"
                consolidationPolicy = "WhenEmptyOrUnderutilized"
                consolidateAfter    = "72h"
                budgets             = [{ nodes = "10%" }]
                labels = merge(local.common_labels, {
                  "node.coder.io/used-for" = "observability-platform"
                })
                expireAfter = "480h"
                taints = [{
                  key    = "platform"
                  value  = "observability-platform"
                  effect = "NoSchedule"
                }]
                requirements = concat(local.common_node_requirements, [{
                  key      = "node.kubernetes.io/instance-type"
                  operator = "In"
                  values   = ["c6g.large", "c6g.xlarge"]
                }])
                nodeClassRef = {
                  group = "eks.amazonaws.com"
                  kind  = "NodeClass"
                  name  = "platform"
                }
              },
              {
                name                = "coder-server"
                consolidationPolicy = "WhenEmptyOrUnderutilized"
                consolidateAfter    = "8h"
                budgets             = [{ nodes = "10%" }]
                labels = merge(local.common_labels, {
                  "node.coder.io/used-for" = "coder-server"
                })
                expireAfter = "480h"
                taints = [{
                  key    = "platform"
                  value  = "coder-server"
                  effect = "NoSchedule"
                }]
                requirements = concat(local.common_node_requirements, [{
                  key      = "node.kubernetes.io/instance-type"
                  operator = "In"
                  values   = ["c6g.xlarge", "c6g.2xlarge", "c6g.4xlarge"]
                }])
                nodeClassRef = {
                  group = "eks.amazonaws.com"
                  kind  = "NodeClass"
                  name  = "platform"
                }
              },
              {
                name                = "coder-provisioner"
                consolidationPolicy = "WhenEmptyOrUnderutilized"
                consolidateAfter    = "8h"
                budgets             = [{ nodes = "100%" }]
                labels = merge(local.common_labels, {
                  "node.coder.io/used-for" = "coder-provisioner"
                })
                expireAfter = "8h"
                taints = [{
                  key    = "coder"
                  value  = "provisioner"
                  effect = "NoSchedule"
                }]
                requirements = concat(local.common_node_requirements, [{
                  key      = "node.kubernetes.io/instance-type"
                  operator = "In"
                  values   = ["c6g.large", "c6g.xlarge", "c6g.2xlarge", "c6g.4xlarge"]
                }])
                nodeClassRef = {
                  group = "eks.amazonaws.com"
                  kind  = "NodeClass"
                  name  = "platform"
                }
              },
              {
                name                = "coder-workspace"
                consolidationPolicy = "WhenEmptyOrUnderutilized"
                consolidateAfter    = "4h"
                budgets             = [{ nodes = "100%" }]
                labels = {
                  "node.coder.io/instance"   = "coder-v2"
                  "node.coder.io/managed-by" = "karpenter"
                  "node.coder.io/name"       = "coder"
                  "node.coder.io/part-of"    = "coder"
                  "node.coder.io/used-for"   = "coder-workspace"
                }
                expireAfter = "Never"
                taints      = []
                requirements = concat(local.common_node_requirements, [{
                  key      = "node.kubernetes.io/instance-type"
                  operator = "In"
                  values   = ["c6a.4xlarge", "c6a.8xlarge"]
                }])
                nodeClassRef = {
                  group = "karpenter.k8s.aws"
                  kind  = "EC2NodeClass"
                  name  = "coder-workspace"
                }
              },
              {
                name                = "coder-workspace-static"
                consolidationPolicy = "WhenEmptyOrUnderutilized"
                consolidateAfter    = "0s"
                budgets             = [{ nodes = "100%" }]
                replicas            = 2
                limits = {
                  nodes = 100
                }
                labels = merge(local.common_labels, {
                  "node.coder.io/used-for" = "coder-workspace-static"
                })
                expireAfter = "Never"
                taints      = []
                requirements = concat(local.common_node_requirements, [{
                  key      = "node.kubernetes.io/instance-type"
                  operator = "In"
                  values   = ["c6a.4xlarge", "c6a.8xlarge"]
                }])
                nodeClassRef = {
                  group = "karpenter.k8s.aws"
                  kind  = "EC2NodeClass"
                  name  = "coder-workspace"
                }
              }
            ]
          })
        }
      }
      destination = {
        server    = data.aws_eks_cluster.this.arn
        namespace = "karpenter"
      }
      syncPolicy = {
        syncOptions = [
          "CreateNamespace=true",
          "Delete=false"
        ]
      }
    }
  }

}