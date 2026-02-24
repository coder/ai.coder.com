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
  public_subnet_cidrs = [ for index, _ in var.azs : cidrsubnet(var.vpc_cidr, 8, index+1) ]
  private_subnet_cidrs = [ for index, _ in var.azs : cidrsubnet(var.vpc_cidr, 2, index+1) ]
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

module "nat" {

  source = "RaJiska/fck-nat/aws"
  version = "~> 1.4.0"

  name      = var.nat_name
  vpc_id    = module.vpc.vpc_id
  subnet_id = module.vpc.public_subnets[0]
  ha_mode   = true # Enables high-availability mode
  use_cloudwatch_agent = true # Enables Cloudwatch agent and have metrics reported

  update_route_tables = true
  route_tables_ids = { 
    for index, _ in var.azs : "rtb-${index}" => module.vpc.private_route_table_ids[index] 
  }
}