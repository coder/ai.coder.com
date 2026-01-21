##
# Kubernetes Infrastructure
##

data "aws_iam_policy_document" "sts" {
  statement {
    effect    = "Allow"
    actions   = ["sts:*"]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "sts" {
  name_prefix = "${var.name}-sts-"
  path        = "/"
  description = "Assume Role Policy"
  policy      = data.aws_iam_policy_document.sts.json
  tags        = local.tags_global
}

locals {
  # Karpenter Security Group Discovery - https://karpenter.sh/v1.0/concepts/nodeclasses/#specsecuritygroupselectorterms
  tags_kptr_sg_discovery = {
    "karpenter.sh/discovery" = var.name
  }
  labels_system_node = {
    "scheduling.coder.com/pool" = "system"
  }
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.14.0"

  vpc_id = module.vpc.vpc_id

  # https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_cluster#vpc_config-1
  # https://docs.aws.amazon.com/eks/latest/userguide/network-reqs.html#network-requirements-subnets
  subnet_ids = toset(concat(
    # local.public_subnet_ids,
    local.private_subnet_ids
  ))

  name                    = var.name

  kubernetes_version      = "1.34"
  endpoint_public_access  = true
  endpoint_private_access = true

  create_security_group      = true
  create_node_security_group = true
  create_iam_role            = true
  node_security_group_tags = local.tags_kptr_sg_discovery

  compute_config = {
    # Disables EKS Auto Mode. Manually handle scaling via Karpenter
    enabled = false 
  }

  attach_encryption_policy                 = false
  create_kms_key                           = false # Enable unless needed
  encryption_config                        = null
  enable_cluster_creator_admin_permissions = true
  enable_irsa                              = true

  eks_managed_node_groups = {
    # Initial nodes are dedicated to system-level processes
    system = {
      min_size     = 0
      max_size     = 10
      desired_size = 3 # Ignored after creation. Override from AWS Console as needed.
      
      # K8s Labels - https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_node_group#labels-1
      labels = local.labels_system_node

      instance_types = ["t3.xlarge"]
      capacity_type  = "ON_DEMAND"
      iam_role_additional_policies = {
        AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
        STSAssumeRole                = aws_iam_policy.sts.arn
      }
      metadata_options = {
        http_endpoint = "enabled"
        http_put_response_hop_limit = 2
        http_tokens = "required"
      }

      # System Nodes should not be public
      subnet_ids = local.private_subnet_ids
    }
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
      })
    }
  }

  tags = local.tags_global
}