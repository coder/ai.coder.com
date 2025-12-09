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

variable "region" {
  description = "The aws region for the vpc"
  type        = string
}

variable "name" {
  description = "Name for created resources and tag prefix"
  type        = string
}

variable "cluster_name" {
  description = "Cluster name"
  type        = string
}

variable "profile" {
  type = string
}

provider "aws" {
  region  = var.region
  profile = var.profile
}

module "vpc" {
  source = "terraform-aws-modules/vpc/aws"
  name   = var.name

  enable_nat_gateway   = false
  enable_dns_hostnames = true

  cidr            = "10.0.0.0/16"
  azs             = ["${var.region}a", "${var.region}b", "${var.region}c"]
  private_subnets = ["10.0.20.0/24", "10.0.21.0/24", "10.0.23.0/24"]
  public_subnets  = ["10.0.10.0/24", "10.0.11.0/24", "10.0.12.0/24"]

  private_subnet_tags = {
    "kubernetes.io/cluster/${var.cluster_name}" : "owned"
  }

  public_subnet_tags = {
    "kubernetes.io/role/elb" : 1
    "kubernetes.io/cluster/${var.cluster_name}" : "owned"
  }
}

module "fck-nat" {
  source = "RaJiska/fck-nat/aws"

  name      = "${var.name}-fck-nat"
  vpc_id    = module.vpc.vpc_id
  subnet_id = module.vpc.public_subnets[0]
  ha_mode   = true # Enables high-availability mode
  # eip_allocation_ids   = ["eipalloc-abc1234"] # Allocation ID of an existing EIP
  use_cloudwatch_agent = true # Enables Cloudwatch agent and have metrics reported

  update_route_tables = true
  route_tables_ids = {
    "route-table1" = module.vpc.private_route_table_ids[0]
    "route-table2" = module.vpc.private_route_table_ids[1]
    "route-table3" = module.vpc.private_route_table_ids[2]
  }
}


## 
# Coder Subnets
##

locals {
  global_subnet_tags = {
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
  }
  coder_server_tags = merge(local.global_subnet_tags, {
    "subnet.coder.io/coder-server/owned-by" = var.cluster_name
  })
  coder_provisioner_tags = merge(local.global_subnet_tags, {
    "subnet.coder.io/coder-provisioner/owned-by" = var.cluster_name
  })
  coder_ws_tags = merge(local.global_subnet_tags, {
    "subnet.coder.io/coder-ws-all/owned-by" = var.cluster_name
  })
}

module "coder-ws-subnet1-az3" {
  source            = "../../../../modules/network/subnet/private"
  name              = var.name
  vpc_id            = module.vpc.vpc_id
  eni_id            = module.fck-nat.eni_id
  cidr_block        = "10.0.16.0/22"
  availability_zone = "${var.region}c"
  subnet_tags       = local.coder_ws_tags
}

module "coder-ws-subnet2-az3" {
  source            = "../../../../modules/network/subnet/private"
  name              = var.name
  vpc_id            = module.vpc.vpc_id
  eni_id            = module.fck-nat.eni_id
  cidr_block        = "10.0.24.0/22"
  availability_zone = "${var.region}c"
  subnet_tags       = local.coder_ws_tags
}

module "coder-ws-subnet3-az3" {
  source            = "../../../../modules/network/subnet/private"
  name              = var.name
  vpc_id            = module.vpc.vpc_id
  eni_id            = module.fck-nat.eni_id
  cidr_block        = "10.0.28.0/22"
  availability_zone = "${var.region}c"
  subnet_tags       = local.coder_ws_tags
}

module "coder-server-subnet1-az1" {
  source            = "../../../../modules/network/subnet/private"
  name              = var.name
  vpc_id            = module.vpc.vpc_id
  eni_id            = module.fck-nat.eni_id
  cidr_block        = "10.0.32.0/22"
  availability_zone = "${var.region}c"
  subnet_tags       = local.coder_server_tags
}

module "coder-server-subnet1-az2" {
  source            = "../../../../modules/network/subnet/private"
  name              = var.name
  vpc_id            = module.vpc.vpc_id
  eni_id            = module.fck-nat.eni_id
  cidr_block        = "10.0.48.0/22"
  availability_zone = "${var.region}b"
  subnet_tags       = local.coder_server_tags
}

module "coder-prov-subnet1-az2" {
  source            = "../../../../modules/network/subnet/private"
  name              = var.name
  vpc_id            = module.vpc.vpc_id
  eni_id            = module.fck-nat.eni_id
  cidr_block        = "10.0.36.0/22"
  availability_zone = "${var.region}c"
  subnet_tags       = local.coder_provisioner_tags
}

##
# Kubernetes System Subnets
## 

locals {
  system_subnet_tags = merge(local.global_subnet_tags, {
    "subnet.amazonaws.io/system/owned-by" = var.name
  })
}

module "system-subnet1-az1" {
  source            = "../../../../modules/network/subnet/private"
  name              = var.name
  vpc_id            = module.vpc.vpc_id
  eni_id            = module.fck-nat.eni_id
  cidr_block        = "10.0.40.0/22"
  availability_zone = "${var.region}a"
  subnet_tags       = local.system_subnet_tags
}

module "system-subnet1-az2" {
  source            = "../../../../modules/network/subnet/private"
  name              = var.name
  vpc_id            = module.vpc.vpc_id
  eni_id            = module.fck-nat.eni_id
  cidr_block        = "10.0.44.0/22"
  availability_zone = "${var.region}b"
  subnet_tags       = local.system_subnet_tags
}

output "region" {
  value       = var.region
  description = "VPC Region"
}

output "vpc_id" {
  value       = module.vpc.vpc_id
  description = "The VPC ID"
}

output "public_subnet_ids" {
  value       = module.vpc.public_subnets
  description = "List of public subnet IDs"
}

output "private_subnet_ids" {
  value       = concat(module.vpc.private_subnets, [])
  description = "List of private subnet IDs"
}

output "other_private_subnet_ids" {
  value = concat([
    module.coder-ws-subnet1-az3.subnet_id,
    module.coder-ws-subnet2-az3.subnet_id,
    module.coder-ws-subnet3-az3.subnet_id,
    module.coder-server-subnet1-az1.subnet_id,
    module.coder-server-subnet1-az2.subnet_id,
    module.coder-prov-subnet1-az2.subnet_id,
    module.system-subnet1-az1.subnet_id,
    module.system-subnet1-az2.subnet_id,
  ])
  description = "List of other private subnet IDs for Coder"
}