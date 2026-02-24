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

provider "aws" {
  region  = var.region
  profile = var.profile
}

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
  storage_type = "gp2"
  allocated_storage = 40
  engine            = "postgres"
  engine_version    = "15.12"
  # backup_retention_period = 7
  username               = var.coder_username
  password               = var.coder_password
  db_name                = "coder"
  db_subnet_group_name   = aws_db_subnet_group.db_subnet_group.name
  vpc_security_group_ids = [aws_security_group.allow-port-5432.id]
  publicly_accessible    = false
  snapshot_identifier = "aidemo-db-2-22-26-7-20-pm-pst"
  final_snapshot_identifier = "snap-${random_id.coder.hex}"
  skip_final_snapshot    = false

  tags = {
    Name = var.coder_db_rds_id
  }
  lifecycle {

    ignore_changes = [
      snapshot_identifier
    ]
  }
}

resource "random_id" "litellm" {
  keepers = {
    id = var.litellm_db_rds_id
  }
  byte_length = 8
}

resource "aws_db_instance" "litellm" {
  identifier             = var.litellm_db_rds_id
  instance_class         = "db.m5.large"
  allocated_storage      = 50
  engine                 = "postgres"
  engine_version         = "15.12"
  username               = var.litellm_username
  password               = var.litellm_password
  db_name                = var.litellm_db_name
  db_subnet_group_name   = aws_db_subnet_group.db_subnet_group.name
  vpc_security_group_ids = [aws_security_group.allow-port-5432.id]
  publicly_accessible    = false
  final_snapshot_identifier = "snap-${random_id.litellm.hex}"
  skip_final_snapshot    = false

  tags = {
    Name = var.litellm_db_rds_id
  }
  lifecycle {
    ignore_changes = [
      snapshot_identifier
    ]
  }
}

resource "random_id" "grafana" {
  keepers = {
    id = var.grafana_db_rds_id
  }
  byte_length = 8
}

resource "aws_db_instance" "grafana" {
  identifier             = var.grafana_db_rds_id
  instance_class         = "db.m5.large"
  allocated_storage      = 50
  engine                 = "postgres"
  engine_version         = "15.12"
  username               = var.grafana_username
  password               = var.grafana_password
  db_name                = var.grafana_db_name
  db_subnet_group_name   = aws_db_subnet_group.db_subnet_group.name
  vpc_security_group_ids = [aws_security_group.allow-port-5432.id]
  publicly_accessible    = false
  final_snapshot_identifier = "snap-${random_id.grafana.hex}"
  skip_final_snapshot    = false

  tags = {
    Name = var.grafana_db_rds_id
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