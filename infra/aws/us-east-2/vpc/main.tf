provider "aws" {
  region  = var.region
  profile = var.profile
}

locals {
  # Subnet Discovery - https://kubernetes-sigs.github.io/aws-load-balancer-controller/latest/deploy/subnet_discovery/#subnet-filtering
  tags_lb_subnet_discovery = {
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
  }
  # Internet-Facing LB - https://kubernetes-sigs.github.io/aws-load-balancer-controller/latest/deploy/subnet_discovery/#subnet-role-tag
  tags_public_lb = {
    "kubernetes.io/role/elb" = 1
  }
  tags_public_subnet = merge(
    local.tags_lb_subnet_discovery,
    local.tags_public_lb
  )
  tags_private_subnet = {
    "karpenter.sh/discovery" = "${var.cluster_name}"
  }
  # Use variable to configure AZ just in case 1 AZ isn't accessible
  # https://repost.aws/questions/QUgdQev4KETKG_Bwev9tMtRQ/is-it-possible-to-enable-3rd-availability-zone-in-us-west-1#AN9eAH55FwTC-NSSp-FjIfTQ
  availability_zones   = [for az in var.azs : "${var.region}${az}"]
  public_subnet_cidrs  = [for index, _ in var.azs : cidrsubnet(var.vpc_cidr, 8, index + 1)]
  private_subnet_cidrs = [for index, _ in var.azs : cidrsubnet(var.vpc_cidr, 2, index + 1)]
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.6.0"

  name = var.vpc_name

  enable_nat_gateway   = false
  enable_dns_hostnames = true

  cidr = var.vpc_cidr
  azs  = local.availability_zones

  public_subnet_suffix = var.public_subnet_suffix
  public_subnets       = [for index, _ in var.azs : local.public_subnet_cidrs[index]]
  public_subnet_tags   = local.tags_public_subnet

  private_subnet_suffix = var.private_subnet_suffix
  private_subnets       = [for index, _ in var.azs : local.private_subnet_cidrs[index]]
  private_subnet_tags   = local.tags_private_subnet

  tags = {}
}

locals {
  endpoints = toset(["ecr.dkr", "ecr.api", "s3"])
}

resource "aws_security_group" "svc-ep" {
  name_prefix = "${var.vpc_name}-vpc-ep"
  description = "Associated to ECR/S3 VPC Endpoints"
  vpc_id      = module.vpc.vpc_id
}

resource "aws_vpc_security_group_ingress_rule" "https" {
  security_group_id = aws_security_group.svc-ep.id
  cidr_ipv4   = module.vpc.vpc_cidr_block
  from_port   = 443
  to_port     = 443
  ip_protocol = "tcp"
}

resource "aws_vpc_endpoint" "svc" {

  for_each = local.endpoints

  vpc_id       = module.vpc.vpc_id
  private_dns_enabled = each.value != "s3"
  service_name = "com.amazonaws.${var.region}.${each.value}"
  vpc_endpoint_type = each.value != "s3" ? "Interface" : "Gateway"
  security_group_ids = each.value != "s3" ? [ aws_security_group.svc-ep.id ] : null
  subnet_ids = each.value != "s3" ? module.vpc.private_subnets : null 
  route_table_ids = each.value == "s3" ? module.vpc.private_route_table_ids : null
}

module "nat" {
  source  = "RaJiska/fck-nat/aws"
  version = "~> 1.4.0"

  name                 = var.nat_name
  vpc_id               = module.vpc.vpc_id
  subnet_id            = module.vpc.public_subnets[0]
  ha_mode              = true # Enables high-availability mode
  use_cloudwatch_agent = true # Enables Cloudwatch agent and have metrics reported
  instance_type = "c7gn.medium"

  update_route_tables = true
  route_tables_ids = {
    for index, _ in var.azs : "rtb-${index}" => module.vpc.private_route_table_ids[index]
  }
}