terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.46"
    }
  }
  backend "s3" {}
}

variable "name" {
  description = "The resource name and tag prefix"
  type        = string
}

variable "profile" {
  type = string
}

variable "region" {
  description = "The aws region to deploy eks cluster"
  type        = string
}

variable "cluster_version" {
  description = "The eks version"
  type        = string
}

variable "cluster_instance_type" {
  description = "EKS Instance Size/Type"
  default     = "t3.xlarge"
  type        = string
}

variable "vpc_id" {
  type      = string
  sensitive = true
}

variable "private_subnet_ids" {
  type      = list(string)
  default   = []
  sensitive = true
}

variable "public_subnet_ids" {
  type      = list(string)
  default   = []
  sensitive = true
}

provider "aws" {
  region  = var.region
  profile = var.profile
}

locals {
  tags = {
    Environment              = "prod"
    Name                     = "${var.name}-eks-cluster"
    "karpenter.sh/discovery" = var.name
  }
  system_subnet_tags = {
    "subnet.amazonaws.io/system/owned-by" = var.name
  }
  provisioner_subnet_tags = {
    "subnet.amazonaws.io/coder-provisioner/owned-by" = var.name
  }
  ws_all_subnet_tags = {
    "subnet.amazonaws.io/coder-ws-all/owned-by" = var.name
  }
  system_sg_tags = {
    "subnet.amazonaws.io/system/owned-by" = var.name
  }
  provisioner_sg_tags = {
    "sg.amazonaws.io/coder-provisioner/owned-by" = var.name
  }
  ws_all_sg_tags = {
    "sg.amazonaws.io/coder-ws-all/owned-by" = var.name
  }
  cluster_asg_node_labels = {
    "node.amazonaws.io/managed-by" = "asg"
  }
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
  version = "~> 20.0"

  vpc_id     = var.vpc_id
  subnet_ids = toset(concat(var.public_subnet_ids, var.private_subnet_ids))

  cluster_name                    = var.name
  cluster_version                 = var.cluster_version
  cluster_endpoint_public_access  = true
  cluster_endpoint_private_access = true

  create_cluster_security_group = true
  create_node_security_group    = true
  create_iam_role               = true
  cluster_addons = {
    coredns = {
      most_recent = true
    }
    kube-proxy = {
      most_recent = true
    }
    vpc-cni = {
      most_recent = true
    }
  }

  attach_cluster_encryption_policy         = false
  create_kms_key                           = false
  cluster_encryption_config                = {}
  enable_cluster_creator_admin_permissions = true
  enable_irsa                              = true

  eks_managed_node_groups = {
    system = {
      min_size     = 0
      max_size     = 10
      desired_size = 0 # Cant be modified after creation. Override from AWS Console
      labels       = local.cluster_asg_node_labels

      instance_types = [var.cluster_instance_type]
      capacity_type  = "ON_DEMAND"
      iam_role_additional_policies = {
        AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
        STSAssumeRole                = aws_iam_policy.sts.arn
      }

      # System Nodes should not be public
      subnet_ids = var.private_subnet_ids
    }
  }

  tags = local.tags
}