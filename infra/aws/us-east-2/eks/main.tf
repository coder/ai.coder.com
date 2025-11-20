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

      # Cost optimization: Graviton ARM instances
      # IMPORTANT: ON_DEMAND for system nodes - production demo cannot break!
      instance_types = [var.cluster_instance_type, "t4g.small", "t4g.large"] # ARM only
      ami_type       = "AL2023_ARM_64_STANDARD"                              # ARM-based AMI
      capacity_type  = "ON_DEMAND"                                           # System infrastructure must be stable

      iam_role_additional_policies = {
        AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
        STSAssumeRole                = aws_iam_policy.sts.arn
      }

      # Cost optimization: gp3 volumes with smaller size
      block_device_mappings = [{
        device_name = "/dev/xvda"
        ebs = {
          volume_type           = "gp3" # Better performance, same cost as gp2
          volume_size           = 20    # Reduced from default 50GB
          delete_on_termination = true
          encrypted             = true
        }
      }]

      # System Nodes should not be public
      subnet_ids = var.private_subnet_ids
    }
  }

  tags = local.tags
}
# VPC Endpoints for cost optimization (reduce NAT Gateway usage)
resource "aws_vpc_endpoint" "s3" {
  vpc_id       = var.vpc_id
  service_name = "com.amazonaws.${var.region}.s3"
  route_table_ids = flatten([
    data.aws_route_tables.private.ids
  ])
  tags = merge(local.tags, {
    Name = "${var.name}-s3-endpoint"
  })
}

resource "aws_vpc_endpoint" "ecr_api" {
  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${var.region}.ecr.api"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.private_subnet_ids
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true
  tags = merge(local.tags, {
    Name = "${var.name}-ecr-api-endpoint"
  })
}

resource "aws_vpc_endpoint" "ecr_dkr" {
  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${var.region}.ecr.dkr"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.private_subnet_ids
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true
  tags = merge(local.tags, {
    Name = "${var.name}-ecr-dkr-endpoint"
  })
}

# Security group for VPC endpoints
resource "aws_security_group" "vpc_endpoints" {
  name_prefix = "${var.name}-vpc-endpoints"
  description = "Security group for VPC endpoints"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, {
    Name = "${var.name}-vpc-endpoints-sg"
  })
}

# Data source for route tables
data "aws_route_tables" "private" {
  vpc_id = var.vpc_id
  filter {
    name   = "tag:Name"
    values = ["*private*"]
  }
}

# Outputs
output "vpc_endpoint_s3_id" {
  description = "S3 VPC Endpoint ID"
  value       = aws_vpc_endpoint.s3.id
}

output "vpc_endpoint_ecr_ids" {
  description = "ECR VPC Endpoint IDs"
  value = {
    api = aws_vpc_endpoint.ecr_api.id
    dkr = aws_vpc_endpoint.ecr_dkr.id
  }
}
