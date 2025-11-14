terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
      # Added version constraint for reproducibility and maintainability
      version = ">= 5.0"
    }
  }
}

data "aws_region" "this" {}

variable "name" {
  description = "Name prefix for VPC and related resources"
  type        = string
  # Validation added because empty name would create invalid resource names
  validation {
    condition     = length(var.name) > 0
    error_message = "name must not be empty"
  }
}

variable "tags" {
  description = "Tags to apply to all resources in this module."
  type        = map(string)
  default     = {}
}

variable "vpc_tags" {
  type    = map(string)
  default = {}
}

variable "vpc_cidr_block" {
  description = "CIDR block for the VPC"
  type        = string
  # Validation added because invalid CIDR would cause VPC creation to fail
  validation {
    condition     = can(cidrhost(var.vpc_cidr_block, 0))
    error_message = "vpc_cidr_block must be a valid CIDR block"
  }
}

variable "vpc_enable_dns_support" {
  type    = bool
  default = true
}

variable "vpc_enable_dns_hostnames" {
  type    = bool
  default = true
}

variable "public_subnets" {
  type = map(object({
    cidr_block                          = string
    availability_zone                   = string
    map_public_ip_on_launch             = optional(bool, false)
    private_dns_hostname_type_on_launch = optional(string, "ip-name")
    tags                                = optional(map(string), {})
  }))
  default = {}
}

variable "private_subnets" {
  type = map(object({
    cidr_block                          = string
    availability_zone                   = string
    private_dns_hostname_type_on_launch = optional(string, "ip-name")
    tags                                = optional(map(string), {})
  }))
  default = {}
}

variable "intra_subnets" {
  type = map(object({
    cidr_block                          = string
    availability_zone                   = string
    private_dns_hostname_type_on_launch = optional(string, "ip-name")
    tags                                = optional(map(string), {})
  }))
  default = {}
}

variable "igw_tags" {
  type    = map(string)
  default = {}
}

variable "nat_tags" {
  type    = map(string)
  default = {}
}

variable "public_rtb_tags" {
  type    = map(string)
  default = {}
}

variable "private_rtb_tags" {
  type    = map(string)
  default = {}
}

variable "intra_rtb_tags" {
  type    = map(string)
  default = {}
}

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr_block
  enable_dns_support   = var.vpc_enable_dns_support
  enable_dns_hostnames = var.vpc_enable_dns_hostnames
  tags                 = merge({ Name = "${var.name}-${data.aws_region.this.name}" }, merge(var.tags, var.vpc_tags))
}

resource "aws_subnet" "public" {
  for_each = var.public_subnets

  vpc_id                              = aws_vpc.this.id
  cidr_block                          = each.value.cidr_block
  availability_zone                   = each.value.availability_zone
  map_public_ip_on_launch             = each.value.map_public_ip_on_launch
  private_dns_hostname_type_on_launch = each.value.private_dns_hostname_type_on_launch
  tags                                = merge({ Name = "${var.name}-public-${each.value.availability_zone}" }, merge(var.tags, each.value.tags))
}

resource "aws_subnet" "private" {
  for_each = var.private_subnets

  vpc_id                              = aws_vpc.this.id
  cidr_block                          = each.value.cidr_block
  availability_zone                   = each.value.availability_zone
  map_public_ip_on_launch             = false
  private_dns_hostname_type_on_launch = each.value.private_dns_hostname_type_on_launch
  tags                                = merge({ Name = "${var.name}-private-${each.value.availability_zone}" }, merge(var.tags, each.value.tags))
}

resource "aws_subnet" "intra" {
  for_each = var.intra_subnets

  vpc_id                              = aws_vpc.this.id
  cidr_block                          = each.value.cidr_block
  availability_zone                   = each.value.availability_zone
  map_public_ip_on_launch             = false
  private_dns_hostname_type_on_launch = each.value.private_dns_hostname_type_on_launch
  tags                                = merge({ Name = "${var.name}-intra-${each.value.availability_zone}" }, merge(var.tags, each.value.tags))
}

# Manage the default SG
resource "aws_default_security_group" "this" {
  vpc_id = aws_vpc.this.id
  tags   = merge(var.tags, var.vpc_tags)

  ingress {
    protocol  = -1
    self      = true
    from_port = 0
    to_port   = 0
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

locals {
  public_subnet_ids  = [for subnet in aws_subnet.public : subnet.id]
  private_subnet_ids = [for subnet in aws_subnet.private : subnet.id]
  intra_subnet_ids   = [for subnet in aws_subnet.intra : subnet.id]
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags   = merge(var.tags, var.igw_tags)
}

module "custom_nat_gateway" {
  source = "../custom-nat"

  name   = "custom-nat-${data.aws_region.this.name}"
  vpc_id = aws_vpc.this.id
  # amazonq-ignore-next-line
  subnet_id            = local.public_subnet_ids[0]
  ha_mode              = true
  use_cloudwatch_agent = true
  update_route_tables  = false
  tags                 = merge(var.tags, var.nat_tags)
}

resource "aws_route_table" "public" {
  count  = length(local.public_subnet_ids) > 0 ? 1 : 0
  vpc_id = aws_vpc.this.id
  tags   = merge(var.tags, var.public_rtb_tags)
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }
}

resource "aws_route_table_association" "public" {
  count          = length(local.public_subnet_ids)
  subnet_id      = element(local.public_subnet_ids, count.index)
  route_table_id = aws_route_table.public[0].id

  # Lifecycle added because missing subnet or route table would cause association to fail
  lifecycle {
    precondition {
      condition     = length(local.public_subnet_ids) > 0 && length(aws_route_table.public) > 0
      error_message = "Public subnets and route table must exist for association"
    }
  }
}

resource "aws_route_table" "private" {
  count  = length(local.private_subnet_ids) > 0 ? 1 : 0
  vpc_id = aws_vpc.this.id
  tags   = merge(var.tags, var.private_rtb_tags)
  route {
    cidr_block           = "0.0.0.0/0"
    network_interface_id = module.custom_nat_gateway.eni_id
  }
}

resource "aws_route_table_association" "private" {
  count          = length(local.private_subnet_ids)
  subnet_id      = element(local.private_subnet_ids, count.index)
  route_table_id = aws_route_table.private[0].id

  # Lifecycle added because missing subnet or route table would cause association to fail
  lifecycle {
    precondition {
      condition     = length(local.private_subnet_ids) > 0 && length(aws_route_table.private) > 0
      error_message = "Private subnets and route table must exist for association"
    }
  }
}

resource "aws_route_table" "intra" {
  count  = length(local.intra_subnet_ids) > 0 ? 1 : 0
  vpc_id = aws_vpc.this.id
  tags   = merge(var.tags, var.intra_rtb_tags)
}

resource "aws_route_table_association" "intra" {
  count          = length(local.intra_subnet_ids)
  subnet_id      = element(local.intra_subnet_ids, count.index)
  route_table_id = aws_route_table.intra[0].id

  # Lifecycle added because missing subnet or route table would cause association to fail
  lifecycle {
    precondition {
      condition     = length(local.intra_subnet_ids) > 0 && length(aws_route_table.intra) > 0
      error_message = "Intra subnets and route table must exist for association"
    }
  }
}

output "vpc_id" {
  value = aws_vpc.this.id
}

output "public_subnet_ids" {
  value = local.public_subnet_ids
}

output "private_subnet_ids" {
  value = local.private_subnet_ids
}

output "intra_subnet_ids" {
  value = local.intra_subnet_ids
}