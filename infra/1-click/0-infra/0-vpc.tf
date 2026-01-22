##
# Networking Infrastructure
## 

variable "azs" {
  type = list(string)
  default = ["a", "b", "c"]
}

locals {
  # Subnet Discovery - https://kubernetes-sigs.github.io/aws-load-balancer-controller/latest/deploy/subnet_discovery/#subnet-filtering
  tags_lb_subnet_discovery = {
    "kubernetes.io/cluster/${var.name}-${local.normalized_domain_name}" = "owned"
  }
  # Internet-Facing LB - https://kubernetes-sigs.github.io/aws-load-balancer-controller/latest/deploy/subnet_discovery/#subnet-role-tag
  tags_public_lb = {
    "kubernetes.io/role/elb"            = 1
  }
  tags_public_subnet = merge(
    local.tags_lb_subnet_discovery,
    local.tags_public_lb
  )
  # Use variable to configure AZ just in case 1 AZ isn't accessible
  # https://repost.aws/questions/QUgdQev4KETKG_Bwev9tMtRQ/is-it-possible-to-enable-3rd-availability-zone-in-us-west-1#AN9eAH55FwTC-NSSp-FjIfTQ
  availability_zones = [ for az in var.azs : "${var.region}${az}" ]
  public_subnet_cidrs = ["10.0.8.0/21", "10.0.4.0/22", "10.0.0.0/22"]
  general_subnet_cidrs = ["10.0.64.0/20", "10.0.80.0/20", "10.0.96.0/20"]
  system_subnet_cidrs = ["10.0.16.0/20", "10.0.32.0/20", "10.0.48.0/20"]
}

module "vpc" {
  source = "terraform-aws-modules/vpc/aws"
  version = "~> 6.6.0"

  name   = "${var.name}-${local.normalized_domain_name}"

  enable_nat_gateway   = false
  enable_dns_hostnames = true

  cidr           = "10.0.0.0/16"
  azs            = local.availability_zones
  
  ##
  # Handle public subnets via the VPC module.
  ##
  public_subnets = [ for index, _ in var.azs : local.public_subnet_cidrs[index] ]
  public_subnet_tags = local.tags_public_subnet

  tags = local.tags_global
}

module "nat-instance" {
  source = "RaJiska/fck-nat/aws"

  name          = "${var.name}-${local.normalized_domain_name}"

  vpc_id        = module.vpc.vpc_id
  subnet_id     = module.vpc.public_subnets[0]
  instance_type = "c6gn.medium"
  ha_mode       = true # Enables high-availability mode
  # eip_allocation_ids   = ["eipalloc-abc1234"] # Allocation ID of an existing EIP
  use_cloudwatch_agent = true # Enables Cloudwatch agent and have metrics reported

  update_route_tables = true
  route_tables_ids    = {}

  tags = local.tags_global
}

## 
# Coder Subnets
##

locals {
  # Karpenter Subnet Discovery - https://karpenter.sh/v1.0/concepts/nodeclasses/#specsubnetselectorterms
  tags_kptr_subnet_discovery = {
    "karpenter.sh/discovery"            = "${var.name}-${local.normalized_domain_name}"
  }
  tags_private_subnet = merge(
    local.tags_lb_subnet_discovery,
    local.tags_kptr_subnet_discovery
  )
}

# 4096 - 5 (reserved by AWS) IPs each

module "general-subnet" {

  count = length(var.azs)

  source            = "../../../modules/network/subnet/private"
  name              = "${var.name}-${local.normalized_domain_name}"
  vpc_id            = module.vpc.vpc_id
  eni_id            = module.nat-instance.eni_id
  cidr_block        = local.general_subnet_cidrs[count.index]
  availability_zone = local.availability_zones[count.index]
  subnet_tags       = local.tags_private_subnet
  tags = local.tags_global
}

##
# Kubernetes System Subnets
## 

module "system-subnet" {

  count = length(var.azs)

  source            = "../../../modules/network/subnet/private"
  name              = "${var.name}-${local.normalized_domain_name}"
  vpc_id            = module.vpc.vpc_id
  eni_id            = module.nat-instance.eni_id
  cidr_block        = local.system_subnet_cidrs[count.index]
  availability_zone = local.availability_zones[count.index]
  subnet_tags       = local.tags_private_subnet
  tags = local.tags_global
}

locals {
  private_subnet_ids = concat(
    module.general-subnet.*.subnet_id, 
    module.system-subnet.*.subnet_id
  )
  public_subnet_ids = concat([], module.vpc.public_subnets)
}