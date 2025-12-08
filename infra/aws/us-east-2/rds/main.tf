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

variable "database_name" {
  description = "Database name"
  type        = string
}

variable "master_username" {
  description = "Database root username"
  type        = string
}

variable "master_password" {
  description = "Database root password"
  type        = string
}

variable "litellm_username" {
  type = string
}

variable "litellm_password" {
  type      = string
  sensitive = true
}

variable "grafana_username" {
  type = string
}

variable "grafana_password" {
  type      = string
  sensitive = true
}

variable "name" {
  description = "Name of resource and tag prefix"
  type        = string
}

variable "region" {
  description = "The aws region for database deployment"
  type        = string
}

variable "private_subnet_ids" {
  description = "The deployed private subnet for the database"
  type        = list(string)
}

variable "vpc_id" {
  description = "The deployed vpc id for the database"
  type        = string
}

variable "allocated_storage" {
  description = "The allocated storage size in gb"
  default     = "20"
  type        = string
}

variable "engine_version" {
  description = "The version to deploy"
  default     = "15.7"
  type        = string
}

variable "instance_class" {
  description = "The size of db instance class to deploy"
  default     = "db.m5.large"
  type        = string
}

variable "profile" {
  type = string
}

provider "aws" {
  region  = var.region
  profile = var.profile
}

# https://developer.hashicorp.com/terraform/tutorials/aws/aws-rds
resource "aws_db_subnet_group" "db_subnet_group" {
  name       = "${var.name}-db-subnet-group"
  subnet_ids = var.private_subnet_ids

  tags = {
    Name = "${var.name}-db-subnet-group"
  }
}

resource "aws_db_instance" "db" {
  identifier        = "${var.name}-db"
  instance_class    = var.instance_class
  allocated_storage = var.allocated_storage
  engine            = "postgres"
  engine_version    = "15.12"
  # backup_retention_period = 7
  username               = var.master_username
  password               = var.master_password
  db_name                = "coder"
  db_subnet_group_name   = aws_db_subnet_group.db_subnet_group.name
  vpc_security_group_ids = [aws_security_group.allow-port-5432.id]
  publicly_accessible    = false
  skip_final_snapshot    = false

  tags = {
    Name = "${var.name}-rds-db"
  }
  lifecycle {
    ignore_changes = [
      snapshot_identifier
    ]
  }
}

resource "aws_db_instance" "litellm" {
  identifier             = "litellm"
  instance_class         = "db.m5.large"
  allocated_storage      = 50
  engine                 = "postgres"
  engine_version         = "15.12"
  username               = var.litellm_username
  password               = var.litellm_password
  db_name                = "litellm"
  db_subnet_group_name   = aws_db_subnet_group.db_subnet_group.name
  vpc_security_group_ids = [aws_security_group.allow-port-5432.id]
  publicly_accessible    = false
  skip_final_snapshot    = false

  tags = {
    Name = "litellm"
  }
  lifecycle {
    ignore_changes = [
      snapshot_identifier
    ]
  }
}

resource "aws_db_instance" "grafana" {
  identifier             = "grafana"
  instance_class         = "db.m5.large"
  allocated_storage      = 50
  engine                 = "postgres"
  engine_version         = "15.12"
  username               = var.grafana_username
  password               = var.grafana_password
  db_name                = "grafana"
  db_subnet_group_name   = aws_db_subnet_group.db_subnet_group.name
  vpc_security_group_ids = [aws_security_group.allow-port-5432.id]
  publicly_accessible    = false
  skip_final_snapshot    = false

  tags = {
    Name = "grafana"
  }
  lifecycle {
    ignore_changes = [
      snapshot_identifier
    ]
  }
}

data "aws_vpc" "this" {
  id = var.vpc_id
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
  vpc_id      = var.vpc_id
  name        = "${var.name}-all-port-5432"
  description = "security group for postgres all egress traffic"
  tags = {
    Name = "${var.name}-postgres-allow-5432"
  }
}

output "rds_port" {
  description = "Database instance port"
  value       = aws_db_instance.db.port
}

output "rds_username" {
  description = "Database instance root username"
  value       = aws_db_instance.db.username
}

output "rds_address" {
  description = "Database instance address"
  value       = aws_db_instance.db.address
}

output "rds_password" {
  description = "Database instance root password"
  value       = aws_db_instance.db.password
  sensitive   = true
}
