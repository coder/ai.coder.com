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

variable "profile" {
  type    = string
  default = "default"
}

variable "requester_vpc_id" {
  description = "VPC ID in us-east-2 (requester)"
  type        = string
}

variable "accepter_vpc_id" {
  description = "VPC ID in us-west-2 (accepter)"
  type        = string
}

variable "requester_vpc_cidr" {
  description = "CIDR block for us-east-2 VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "accepter_vpc_cidr" {
  description = "CIDR block for us-west-2 VPC"
  type        = string
  default     = "10.1.0.0/16"
}

variable "requester_node_security_group_id" {
  description = "Security group ID for EKS nodes in us-east-2"
  type        = string
}

variable "accepter_node_security_group_id" {
  description = "Security group ID for EKS nodes in us-west-2"
  type        = string
}

# Provider for us-east-2 (requester)
provider "aws" {
  alias   = "use2"
  region  = "us-east-2"
  profile = var.profile
}

# Provider for us-west-2 (accepter)
provider "aws" {
  alias   = "usw2"
  region  = "us-west-2"
  profile = var.profile
}

# Create VPC peering connection from us-east-2
resource "aws_vpc_peering_connection" "use2_to_usw2" {
  provider = aws.use2

  vpc_id      = var.requester_vpc_id
  peer_vpc_id = var.accepter_vpc_id
  peer_region = "us-west-2"
  auto_accept = false

  tags = {
    Name      = "coderdemo-use2-usw2-peering"
    ManagedBy = "terraform"
    Side      = "Requester"
  }
}

# Accept the peering connection in us-west-2
resource "aws_vpc_peering_connection_accepter" "usw2_accepter" {
  provider = aws.usw2

  vpc_peering_connection_id = aws_vpc_peering_connection.use2_to_usw2.id
  auto_accept               = true

  tags = {
    Name      = "coderdemo-use2-usw2-peering"
    ManagedBy = "terraform"
    Side      = "Accepter"
  }
}

# Get route tables in us-east-2
data "aws_route_tables" "use2" {
  provider = aws.use2
  vpc_id   = var.requester_vpc_id
}

# Get route tables in us-west-2
data "aws_route_tables" "usw2" {
  provider = aws.usw2
  vpc_id   = var.accepter_vpc_id
}

# Add routes in us-east-2 route tables to us-west-2 CIDR
resource "aws_route" "use2_to_usw2" {
  provider = aws.use2
  for_each = toset(data.aws_route_tables.use2.ids)

  route_table_id            = each.value
  destination_cidr_block    = var.accepter_vpc_cidr
  vpc_peering_connection_id = aws_vpc_peering_connection.use2_to_usw2.id

  depends_on = [aws_vpc_peering_connection_accepter.usw2_accepter]
}

# Add routes in us-west-2 route tables to us-east-2 CIDR
resource "aws_route" "usw2_to_use2" {
  provider = aws.usw2
  for_each = toset(data.aws_route_tables.usw2.ids)

  route_table_id            = each.value
  destination_cidr_block    = var.requester_vpc_cidr
  vpc_peering_connection_id = aws_vpc_peering_connection.use2_to_usw2.id

  depends_on = [aws_vpc_peering_connection_accepter.usw2_accepter]
}

# Security group rule to allow Coder replica communication from us-west-2 to us-east-2
resource "aws_security_group_rule" "use2_allow_coder_from_usw2" {
  provider = aws.use2

  type              = "ingress"
  from_port         = 8080
  to_port           = 8080
  protocol          = "tcp"
  cidr_blocks       = [var.accepter_vpc_cidr]
  security_group_id = var.requester_node_security_group_id
  description       = "Allow Coder replica communication from us-west-2"
}

# Security group rule to allow Coder replica communication from us-east-2 to us-west-2
resource "aws_security_group_rule" "usw2_allow_coder_from_use2" {
  provider = aws.usw2

  type              = "ingress"
  from_port         = 8080
  to_port           = 8080
  protocol          = "tcp"
  cidr_blocks       = [var.requester_vpc_cidr]
  security_group_id = var.accepter_node_security_group_id
  description       = "Allow Coder replica communication from us-east-2"
}

# Outputs
output "peering_connection_id" {
  description = "VPC Peering Connection ID"
  value       = aws_vpc_peering_connection.use2_to_usw2.id
}

output "peering_status" {
  description = "VPC Peering Connection Status"
  value       = aws_vpc_peering_connection.use2_to_usw2.accept_status
}
