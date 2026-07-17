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