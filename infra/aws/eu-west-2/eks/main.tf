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

  vpc_id     = data.aws_vpc.this.id
  subnet_ids = toset(concat( 
    data.aws_subnets.private.ids 
  ))

  name                    = var.name
  kubernetes_version                 = var.eks_version
  endpoint_public_access  = true
  endpoint_private_access = true

  create_security_group         = true
  create_node_security_group    = true
  create_iam_role               = true
  node_security_group_tags      = local.tags_kptr_sg_discovery
  create_node_iam_role          = true
  node_iam_role_use_name_prefix = true

  compute_config = {
    enabled    = true
    node_pools = ["system"]
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