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

data "aws_iam_policy_document" "ecr-mirror" {

  statement {
    effect    = "Allow"
    actions   = ["ecr:CreateRepository"]
    resources = ["*"]
  }

  statement {
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    effect = "Allow"
    actions = [
      "ecr:BatchImportUpstreamImage",
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer"
    ]
    resources = ["arn:aws:ecr:${var.region}:${data.aws_caller_identity.me.account_id}:repository/cache/*"]
  }
}

resource "aws_iam_policy" "ecr-mirror" {
  name_prefix = "ecr-mirror"
  description = "Allows ECR pull-through cache automation including repository creation"
  path        = "/${var.region}/kptr/"
  policy      = data.aws_iam_policy_document.ecr-mirror.json
}

locals {
  std_karpenter_format = "kptr"
  karpenter_queue_name = "${var.cluster_name}-kptr"
  # karpenter_queue_rule_name        = "${var.cluster_name}-kptr"
  karpenter_controller_role_name   = "${local.std_karpenter_format}-ctrl"
  karpenter_controller_policy_name = local.std_karpenter_format
  karpenter_node_role_name         = "${local.std_karpenter_format}-node"
}

data "aws_iam_policy_document" "sts" {
  statement {
    effect    = "Allow"
    actions   = ["sts:*"]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "sts" {
  name_prefix = "${var.cluster_name}-sts-"
  path        = "/${var.cluster_name}/${data.aws_region.this.region}/${local.std_karpenter_format}/"
  description = "Assume Role Policy"
  policy      = data.aws_iam_policy_document.sts.json
}

locals {
  cluster_oidc_provider = trimprefix(data.aws_iam_openid_connect_provider.this.url, "https://")
}

data "aws_iam_policy_document" "kptr_ctrl_assume_role_policy" {
  statement {
    effect = "Allow"

    principals {
      type        = "Federated"
      identifiers = [data.aws_iam_openid_connect_provider.this.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.cluster_oidc_provider}:sub"
      values   = ["system:serviceaccount:karpenter:karpenter"]
    }

    # https://aws.amazon.com/premiumsupport/knowledge-center/eks-troubleshoot-oidc-and-irsa/?nc1=h_ls
    condition {
      test     = "StringEquals"
      variable = "${local.cluster_oidc_provider}:aud"
      values   = ["sts.amazonaws.com"]
    }

    actions = ["sts:AssumeRoleWithWebIdentity"]
  }
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
  iam_role_path            = "/${var.cluster_name}/${data.aws_region.this.region}/"
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
  node_iam_role_path            = "/${var.cluster_name}/${data.aws_region.this.region}/"
  node_iam_role_additional_policies = {
    AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
    STSAssumeRole                = aws_iam_policy.sts.arn
    ECRMirrorPolicy              = aws_iam_policy.ecr-mirror.arn
  }

  create_pod_identity_association = false
  enable_spot_termination         = true
}

resource "kubernetes_namespace_v1" "karpenter" {
  metadata {
    name = "karpenter"
  }
}

import {
  id = "karpenter"
  to = kubernetes_namespace_v1.karpenter
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
      name        = "karpenter"
      namespace   = "argocd"
      labels      = {}
      annotations = {}
      finalizers  = ["resources-finalizers.argocd.argoproj.io"]
    }
    spec = {
      project = "default"
      source = {
        repoURL        = "https://github.com/coder/ai.coder.com"
        path           = "infra/aws/us-east-2/k8s/argo/karpenter/charts/karpenter"
        targetRevision = "main"
        helm = {
          values = [yamlencode({
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
          })]
        }
      }
      destination = {
        server    = data.aws_eks_cluster.this.arn
        namespace = kubernetes_namespace_v1.karpenter.metadata[0].name
      }
      syncPolicy = {
        syncOptions = [
          "CreateNamespace=false",
          "Delete=false"
        ]
      }
    }
  }

}