##
# Networking Infrastructure
##

locals {
  # Subnet Discovery - https://kubernetes-sigs.github.io/aws-load-balancer-controller/latest/deploy/subnet_discovery/#subnet-filtering
  tags_lb_subnet_discovery = {
    "kubernetes.io/cluster/${local.formatted_name}" = "owned"
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
    "karpenter.sh/discovery" = "${local.formatted_name}"
  }
  # Use variable to configure AZ just in case 1 AZ isn't accessible
  # https://repost.aws/questions/QUgdQev4KETKG_Bwev9tMtRQ/is-it-possible-to-enable-3rd-availability-zone-in-us-west-1#AN9eAH55FwTC-NSSp-FjIfTQ
  availability_zones   = [for az in var.azs : "${var.region}${az}"]
  public_subnet_cidrs  = ["10.0.8.0/21", "10.0.4.0/22", "10.0.0.0/22"]
  private_subnet_cidrs = ["10.0.64.0/20", "10.0.80.0/20", "10.0.96.0/20"]
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.6.0"

  name = local.formatted_name

  enable_nat_gateway   = true
  enable_dns_hostnames = true

  cidr = "10.0.0.0/16"
  azs  = local.availability_zones

  public_subnet_suffix = "public"
  public_subnets       = [for index, _ in var.azs : local.public_subnet_cidrs[index]]
  public_subnet_tags   = local.tags_public_subnet

  private_subnet_suffix = "private"
  private_subnets       = [for index, _ in var.azs : local.private_subnet_cidrs[index]]
  private_subnet_tags   = local.tags_private_subnet

  tags = {}
}