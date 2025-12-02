terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.100.0"
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
  default     = "t4g.medium" # ARM Graviton for cost optimization
  type        = string
}

variable "allowed_cidrs" {
  description = "CIDR blocks allowed to access EKS API endpoint"
  type        = list(string)
  default     = ["0.0.0.0/0"] # Open by default, restrict in tfvars
}

provider "aws" {
  region  = var.region
  profile = var.profile
}

##
# Cluster Infrastructure
##

locals {
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

data "aws_region" "this" {}

module "eks-network" {
  source = "../../../../modules/network/eks-vpc"

  name           = var.name
  vpc_cidr_block = "10.1.0.0/16"
  public_subnets = {
    "system0" = {
      cidr_block                          = "10.1.10.0/24"
      availability_zone                   = "${data.aws_region.this.name}a"
      map_public_ip_on_launch             = true
      private_dns_hostname_type_on_launch = "ip-name"
    }
    "system1" = {
      cidr_block                          = "10.1.11.0/24"
      availability_zone                   = "${data.aws_region.this.name}b"
      map_public_ip_on_launch             = true
      private_dns_hostname_type_on_launch = "ip-name"
    }
  }
  private_subnets = {
    "system0" = {
      cidr_block                          = "10.1.20.0/24"
      availability_zone                   = "${data.aws_region.this.name}a"
      private_dns_hostname_type_on_launch = "ip-name"
      tags                                = local.system_subnet_tags
    }
    "system1" = {
      cidr_block                          = "10.1.21.0/24"
      availability_zone                   = "${data.aws_region.this.name}b"
      private_dns_hostname_type_on_launch = "ip-name"
      tags                                = local.system_subnet_tags
    }
    "provisioner" = {
      cidr_block                          = "10.1.22.0/24"
      availability_zone                   = "${data.aws_region.this.name}a"
      map_public_ip_on_launch             = true
      private_dns_hostname_type_on_launch = "ip-name"
      tags                                = local.provisioner_subnet_tags
    }
    "ws-all" = {
      cidr_block                          = "10.1.16.0/22"
      availability_zone                   = "${data.aws_region.this.name}b"
      map_public_ip_on_launch             = true
      private_dns_hostname_type_on_launch = "ip-name"
      tags                                = local.ws_all_subnet_tags
    }
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
}

module "cluster" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  vpc_id = module.eks-network.vpc_id
  subnet_ids = toset(concat(concat(
    module.eks-network.public_subnet_ids,
    module.eks-network.private_subnet_ids),
    module.eks-network.intra_subnet_ids
  ))

  cluster_name                         = var.name
  cluster_version                      = var.cluster_version
  cluster_endpoint_public_access       = true
  cluster_endpoint_private_access      = true
  cluster_endpoint_public_access_cidrs = var.allowed_cidrs

  create_cluster_security_group = true
  create_node_security_group    = true
  node_security_group_tags = merge(
    local.system_sg_tags,
    merge(local.provisioner_sg_tags, local.ws_all_sg_tags)
  )
  create_iam_role = true
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

  # Disable KMS, speed up cluster creation times. Enable if encryption is necessary.
  attach_cluster_encryption_policy         = false
  create_kms_key                           = false
  cluster_encryption_config                = {}
  enable_cluster_creator_admin_permissions = true
  enable_irsa                              = true

  eks_managed_node_groups = {
    system = {
      min_size     = 0
      max_size     = 10
      desired_size = 1 # Scale to 1 node for cluster functionality
      labels       = local.cluster_asg_node_labels

      instance_types = [var.cluster_instance_type]
      capacity_type  = "ON_DEMAND"
      ami_type       = "AL2023_ARM_64_STANDARD" # ARM AMI for Graviton instances
      iam_role_additional_policies = {
        AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
        STSAssumeRole                = aws_iam_policy.sts.arn
      }

      # System Nodes should not be public
      subnet_ids = module.eks-network.private_subnet_ids
    }
  }
}