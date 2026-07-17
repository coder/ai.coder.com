provider "aws" {
  region  = var.region
  profile = var.profile
}

data "aws_vpc" "this" {
  tags = {
    Name = var.vpc_name
  }
}

data "aws_subnets" "public" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.this.id]
  }

  tags = {
    Name = "*${var.public_subnet_suffix}*"
  }
}

data "aws_caller_identity" "me" {}

data "aws_subnets" "private" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.this.id]
  }

  tags = {
    Name = "*${var.private_subnet_suffix}*"
  }
}

locals {
  tags = {
    Name                     = var.name
    "karpenter.sh/discovery" = var.name
  }
  # Karpenter Security Group Discovery - https://karpenter.sh/v1.0/concepts/nodeclasses/#specsecuritygroupselectorterms
  tags_kptr_sg_discovery = {
    "karpenter.sh/discovery" = var.name
  }
  labels_system_node = {
    "scheduling.coder.com/pool" = "system"
  }
  taints_system = {
    key    = "CriticalAddonsOnly"
    effect = "NO_SCHEDULE"
  }
  tolerations_system = [{
    key      = "CriticalAddonsOnly"
    operator = "Exists"
  }]
}

data "aws_iam_policy_document" "sts" {
  statement {
    effect    = "Allow"
    actions   = ["sts:*"]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "sts" {
  name_prefix = "sts"
  path        = "/"
  description = "Assume Role Policy"
  policy      = data.aws_iam_policy_document.sts.json
  tags        = local.tags
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.15.1"

  vpc_id = data.aws_vpc.this.id
  subnet_ids = toset(concat(
    data.aws_subnets.private.ids
  ))

  name                    = var.name
  kubernetes_version      = var.eks_version
  endpoint_public_access  = true
  endpoint_private_access = true

  create_security_group         = true
  create_node_security_group    = true
  create_iam_role               = true
  node_security_group_tags      = local.tags_kptr_sg_discovery
  create_node_iam_role          = true
  node_iam_role_use_name_prefix = true

  create_auto_mode_iam_resources = true
  compute_config = {
    enabled = true
  }

  addons = {
    coredns = {
      before_compute = true
    }
    kube-proxy = {
      before_compute = true
    }
    vpc-cni = {
      before_compute = true
      configuration_values = jsonencode({
        enableNetworkPolicy = "true"
        nodeAgent = {
          enablePolicyEventLogs = "true"
        }
        env = {
          ENABLE_PREFIX_DELEGATION = "true"
          WARM_PREFIX_TARGET       = "1"
          WARM_IP_TARGET           = "0"
          AWS_VPC_K8S_CNI_LOGLEVEL = "DEBUG"
        }
      })
    }
  }

  attach_encryption_policy                 = false
  create_kms_key                           = false # Enable unless needed
  encryption_config                        = null
  enable_cluster_creator_admin_permissions = true
  enable_irsa                              = true

  eks_managed_node_groups = {
    system = {
      min_size     = 0
      max_size     = 10
      desired_size = 0 # Cant be modified after creation. Override from AWS Console
      labels       = local.labels_system_node

      instance_types = [var.instance_type]
      capacity_type  = "ON_DEMAND"
      iam_role_additional_policies = {
        AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
        STSAssumeRole                = aws_iam_policy.sts.arn
      }

      # System Nodes should not be public
      subnet_ids = data.aws_subnets.private.ids
    }
  }

  tags = local.tags
}

resource "aws_eks_access_entry" "argocd" {
  principal_arn = "arn:aws:iam::${data.aws_caller_identity.me.account_id}:role/ArgoCDCapabilityRole-${var.name}"
  cluster_name  = module.eks.cluster_name
  type          = "STANDARD"
}

locals {
  argocd_cluster_policies = [
    "AmazonEKSClusterAdminPolicy",
    "AmazonEKSArgoCDClusterPolicy",
    "AmazonEKSArgoCDPolicy"
  ]
}

resource "aws_eks_access_policy_association" "argocd" {

  for_each = toset(local.argocd_cluster_policies)

  cluster_name  = module.eks.cluster_name
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/${each.value}"
  principal_arn = "arn:aws:iam::${data.aws_caller_identity.me.account_id}:role/ArgoCDCapabilityRole-${var.name}"

  access_scope {
    type = "cluster"
  }
}

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    args        = ["eks", "get-token", "--cluster-name", var.name, "--region", var.region, "--profile", var.profile]
    command     = "aws"
  }
}

resource "kubernetes_manifest" "default-class" {

  depends_on = [module.eks]

  manifest = {
    apiVersion = "eks.amazonaws.com/v1"
    kind       = "NodeClass"

    metadata = {
      name = "coder-default"
      labels = {
        "app.kubernetes.io/managed-by" = "terraform"
      }
    }

    spec = {
      ephemeralStorage = {
        iops       = 3000
        size       = "80Gi"
        throughput = 125
      }

      networkPolicy          = "DefaultAllow"
      networkPolicyEventLogs = "Disabled"
      snatPolicy             = "Disabled"

      role = module.eks.node_iam_role_name

      securityGroupSelectorTerms = [
        {
          id = module.eks.cluster_primary_security_group_id
        }
      ]

      subnetSelectorTerms = [for subnet_id in data.aws_subnets.private.ids : { id = subnet_id }]
    }
  }
}

# Override the System NodePool to restrict number of nodess
resource "kubernetes_manifest" "system-pool" {

  depends_on = [module.eks]

  manifest = {
    apiVersion = "karpenter.sh/v1"
    kind       = "NodePool"

    metadata = {
      name = "coder-system"
      labels = {
        "app.kubernetes.io/managed-by" = "terraform"
      }
    }

    spec = {
      disruption = {
        budgets = [
          {
            nodes = "10%"
          }
        ]
        consolidateAfter    = "30s"
        consolidationPolicy = "WhenEmptyOrUnderutilized"
      }

      limits = {
        nodes = 4
      }

      template = {
        metadata = {}

        spec = {
          expireAfter = "336h"

          nodeClassRef = {
            group = split("/", kubernetes_manifest.default-class.manifest.apiVersion)[0]
            kind  = kubernetes_manifest.default-class.manifest.kind
            name  = kubernetes_manifest.default-class.manifest.metadata.name
          }

          requirements = [
            {
              key      = "karpenter.sh/capacity-type"
              operator = "In"
              values   = ["on-demand"]
            },
            {
              key      = "eks.amazonaws.com/instance-category"
              operator = "In"
              values   = ["c", "m", "r"]
            },
            {
              key      = "eks.amazonaws.com/instance-generation"
              operator = "Gt"
              values   = ["4"]
            },
            {
              key      = "kubernetes.io/arch"
              operator = "In"
              values   = ["amd64", "arm64"]
            },
            {
              key      = "topology.kubernetes.io/zone"
              operator = "In"
              values   = slice([for az in var.azs : "${var.region}${az}"], 0, 1)
            },
            {
              key      = "kubernetes.io/os"
              operator = "In"
              values   = ["linux"]
            }
          ]

          taints = [
            {
              key    = "CriticalAddonsOnly"
              effect = "NoSchedule"
            }
          ]

          terminationGracePeriod = "24h0m0s"
        }
      }
    }
  }
}

output "azs" {
  value = join(", ", slice([for az in var.azs : "${var.region}${az}"], 0, 1))
}