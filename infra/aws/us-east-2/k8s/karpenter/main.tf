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

locals {
  global_node_labels = {
    "node.coder.io/instance"   = "coder-v2"
    "node.coder.io/managed-by" = "karpenter"
  }
  global_node_reqs = [{
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
  }]
  provisioner_subnet_tags = {
    "subnet.coder.io/coder-provisioner/owned-by" = var.cluster_name
  }
  ws_all_subnet_tags = {
    "subnet.coder.io/coder-ws-all/owned-by" = var.cluster_name
  }
  provisioner_sg_tags = {
    # "sg.amazonaws.io/coder-provisioner/owned-by" = var.cluster_name
    "karpenter.sh/discovery" : var.cluster_name
  }
  ws_all_sg_tags = {
    # "sg.amazonaws.io/coder-ws-all/owned-by" = var.cluster_name
    "karpenter.sh/discovery" : var.cluster_name
  }
}

data "aws_iam_policy_document" "ecr-mirror" {
  
  statement {
    effect  = "Allow"
    actions = ["ecr:CreateRepository"]
    resources = ["*"]
  }

  statement {
    effect  = "Allow"
    actions = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    effect  = "Allow"
    actions = [
      "ecr:BatchImportUpstreamImage",
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer"
    ]
    resources = [ "arn:aws:ecr:${var.region}:${data.aws_caller_identity.me.account_id}:repository/cache/*" ]
  }
}

resource "aws_iam_policy" "ecr-mirror" {
  name_prefix        = "ecr-mirror"
  description = "Allows ECR pull-through cache automation including repository creation"
  path = "/${var.region}/kptr/"
  policy      = data.aws_iam_policy_document.ecr-mirror.json
}

module "karpenter-addon" {

  source                    = "../../../../../modules/k8s/bootstrap/karpenter"
  cluster_name              = var.cluster_name
  cluster_oidc_provider     = trimprefix(data.aws_iam_openid_connect_provider.this.url, "https://")
  cluster_oidc_provider_arn = data.aws_iam_openid_connect_provider.this.arn

  namespace     = var.addon_namespace
  chart_version = var.addon_version

  node_selector = {}
  tolerations = [{
    key      = "CriticalAddonsOnly"
    operator = "Exists"
  }]
  topology_spread = []
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

  iam_role_use_name_prefix      = true
  node_iam_role_use_name_prefix = true
  replicas                      = 2
  karpenter_controller_role_policies = {
    "AmazonEFSCSIDriverPolicy" = "arn:aws:iam::aws:policy/service-role/AmazonEFSCSIDriverPolicy"
  }
  karpenter_node_role_policies = {
    "ECRMirrorPolicy" = aws_iam_policy.ecr-mirror.arn
  }
}