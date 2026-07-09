provider "aws" {
  region  = var.region
  profile = var.profile
}

data "aws_vpc" "this" {
  tags = {
    Name = var.vpc_name
  }
}

data "aws_subnets" "private" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.this.id]
  }

  tags = {
    Name = "*${var.private_subnet_suffix}*"
  }
}

data "aws_region" "this" {}
data "aws_caller_identity" "this" {}

# https://developer.hashicorp.com/terraform/tutorials/aws/aws-rds
resource "aws_db_subnet_group" "db_subnet_group" {
  name       = var.db_subnet_group_name
  subnet_ids = data.aws_subnets.private.ids

  tags = {
    Name = var.db_subnet_group_name
  }
}

resource "random_id" "coder" {
  keepers = {
    id = var.coder_db_rds_id
  }
  byte_length = 8
}

resource "aws_db_instance" "coder" {
  identifier        = var.coder_db_rds_id
  instance_class    = var.instance_class
  storage_type      = "gp2"
  allocated_storage = 40
  engine            = "postgres"
  engine_version    = "15.17"
  # backup_retention_period = 7
  username                  = var.coder_username
  db_name                   = "coder"
  db_subnet_group_name      = aws_db_subnet_group.db_subnet_group.name
  vpc_security_group_ids    = [aws_security_group.allow-port-5432.id]
  publicly_accessible       = false
  snapshot_identifier       = "aidemo-db-2-22-26-7-20-pm-pst"
  final_snapshot_identifier = "snap-${random_id.coder.hex}"
  skip_final_snapshot       = false

  iam_database_authentication_enabled = true
  apply_immediately = true
  manage_master_user_password = true

  tags = {
    Name = var.coder_db_rds_id
  }
  lifecycle {
    ignore_changes = [
      snapshot_identifier
    ]
  }
}

resource "aws_vpc_security_group_ingress_rule" "postgres" {
  security_group_id = aws_security_group.allow-port-5432.id
  cidr_ipv4         = data.aws_vpc.this.cidr_block
  ip_protocol       = "tcp"
  from_port         = 5432
  to_port           = 5432
}

resource "aws_vpc_security_group_egress_rule" "all" {
  security_group_id = aws_security_group.allow-port-5432.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = -1
}

resource "aws_security_group" "allow-port-5432" {
  vpc_id      = data.aws_vpc.this.id
  name        = "rds-traffic"
  description = "security group for postgres all egress traffic"
  tags = {
    Name = "rds-traffic"
  }
}