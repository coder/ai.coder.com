terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.46"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
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

variable "litellm_username" {
  type = string
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

# Generate secure random passwords
resource "random_password" "coder_master_password" {
  length  = 32
  special = true
}

resource "random_password" "litellm_password" {
  length  = 32
  special = true
}

# https://developer.hashicorp.com/terraform/tutorials/aws/aws-rds
resource "aws_db_subnet_group" "db_subnet_group" {
  name       = "${var.name}-db-subnet-group"
  subnet_ids = var.private_subnet_ids

  tags = {
    Name = "${var.name}-db-subnet-group"
  }
}

# Aurora Serverless v2 Cluster for Coder
resource "aws_rds_cluster" "coder" {
  cluster_identifier      = "${var.name}-aurora-cluster"
  engine                  = "aurora-postgresql"
  engine_mode             = "provisioned"
  engine_version          = "15.8"
  database_name           = "coder"
  master_username         = var.master_username
  master_password         = random_password.coder_master_password.result
  db_subnet_group_name    = aws_db_subnet_group.db_subnet_group.name
  vpc_security_group_ids  = [aws_security_group.allow-port-5432.id]
  backup_retention_period = 7
  preferred_backup_window = "03:00-04:00"
  skip_final_snapshot     = false
  storage_encrypted       = true

  serverlessv2_scaling_configuration {
    min_capacity = 0.5 # 0.5 ACU = 1 GB RAM (idle state)
    max_capacity = 16  # 16 ACU = 32 GB RAM (handles 5K-10K users)
  }

  tags = {
    Name = "${var.name}-aurora-coder"
  }
}

# Aurora Serverless v2 Instance for Coder (Multi-AZ with 2 instances)
resource "aws_rds_cluster_instance" "coder_writer" {
  identifier           = "${var.name}-aurora-coder-writer"
  cluster_identifier   = aws_rds_cluster.coder.id
  instance_class       = "db.serverless"
  engine               = aws_rds_cluster.coder.engine
  engine_version       = "15.8"
  publicly_accessible  = false
  db_subnet_group_name = aws_db_subnet_group.db_subnet_group.name

  tags = {
    Name = "${var.name}-aurora-coder-writer"
  }
}

resource "aws_rds_cluster_instance" "coder_reader" {
  identifier           = "${var.name}-aurora-coder-reader"
  cluster_identifier   = aws_rds_cluster.coder.id
  instance_class       = "db.serverless"
  engine               = aws_rds_cluster.coder.engine
  engine_version       = "15.8"
  publicly_accessible  = false
  db_subnet_group_name = aws_db_subnet_group.db_subnet_group.name

  tags = {
    Name = "${var.name}-aurora-coder-reader"
  }
}

# Aurora Serverless v2 Cluster for LiteLLM
resource "aws_rds_cluster" "litellm" {
  cluster_identifier      = "litellm-aurora-cluster"
  engine                  = "aurora-postgresql"
  engine_mode             = "provisioned"
  engine_version          = "15.8"
  database_name           = "litellm"
  master_username         = var.litellm_username
  master_password         = random_password.litellm_password.result
  db_subnet_group_name    = aws_db_subnet_group.db_subnet_group.name
  vpc_security_group_ids  = [aws_security_group.allow-port-5432.id]
  backup_retention_period = 7
  preferred_backup_window = "04:00-05:00"
  skip_final_snapshot     = false
  storage_encrypted       = true

  serverlessv2_scaling_configuration {
    min_capacity = 0.5 # 0.5 ACU = 1 GB RAM (idle state)
    max_capacity = 8   # 8 ACU = 16 GB RAM (handles moderate usage)
  }

  tags = {
    Name = "litellm-aurora"
  }
}

# Aurora Serverless v2 Instance for LiteLLM
resource "aws_rds_cluster_instance" "litellm_writer" {
  identifier           = "litellm-aurora-writer"
  cluster_identifier   = aws_rds_cluster.litellm.id
  instance_class       = "db.serverless"
  engine               = aws_rds_cluster.litellm.engine
  engine_version       = "15.8"
  publicly_accessible  = false
  db_subnet_group_name = aws_db_subnet_group.db_subnet_group.name

  tags = {
    Name = "litellm-aurora-writer"
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

# No egress rules needed - RDS only responds to inbound connections
# This follows security best practice of least privilege

resource "aws_security_group" "allow-port-5432" {
  vpc_id      = var.vpc_id
  name        = "${var.name}-all-port-5432"
  description = "security group for postgres all egress traffic"
  tags = {
    Name = "${var.name}-postgres-allow-5432"
  }
}

# Store Coder DB credentials in Secrets Manager
resource "aws_secretsmanager_secret" "coder_db" {
  name_prefix             = "${var.name}-coder-db-"
  description             = "Coder PostgreSQL database credentials"
  recovery_window_in_days = 7

  tags = {
    Name = "${var.name}-coder-db-secret"
  }
}

resource "aws_secretsmanager_secret_version" "coder_db" {
  secret_id = aws_secretsmanager_secret.coder_db.id
  secret_string = jsonencode({
    username       = var.master_username
    password       = random_password.coder_master_password.result
    host           = aws_rds_cluster.coder.endpoint
    reader_host    = aws_rds_cluster.coder.reader_endpoint
    port           = aws_rds_cluster.coder.port
    dbname         = aws_rds_cluster.coder.database_name
    url            = "postgres://${var.master_username}:${random_password.coder_master_password.result}@${aws_rds_cluster.coder.endpoint}:${aws_rds_cluster.coder.port}/${aws_rds_cluster.coder.database_name}?sslmode=require"
    reader_url     = "postgres://${var.master_username}:${random_password.coder_master_password.result}@${aws_rds_cluster.coder.reader_endpoint}:${aws_rds_cluster.coder.port}/${aws_rds_cluster.coder.database_name}?sslmode=require"
    cluster_id     = aws_rds_cluster.coder.id
    engine_version = aws_rds_cluster.coder.engine_version
  })
}

# Store LiteLLM DB credentials in Secrets Manager
resource "aws_secretsmanager_secret" "litellm_db" {
  name_prefix             = "litellm-db-"
  description             = "LiteLLM PostgreSQL database credentials"
  recovery_window_in_days = 7

  tags = {
    Name = "litellm-db-secret"
  }
}

resource "aws_secretsmanager_secret_version" "litellm_db" {
  secret_id = aws_secretsmanager_secret.litellm_db.id
  secret_string = jsonencode({
    username       = var.litellm_username
    password       = random_password.litellm_password.result
    host           = aws_rds_cluster.litellm.endpoint
    reader_host    = aws_rds_cluster.litellm.reader_endpoint
    port           = aws_rds_cluster.litellm.port
    dbname         = aws_rds_cluster.litellm.database_name
    url            = "postgres://${var.litellm_username}:${random_password.litellm_password.result}@${aws_rds_cluster.litellm.endpoint}:${aws_rds_cluster.litellm.port}/${aws_rds_cluster.litellm.database_name}?sslmode=require"
    cluster_id     = aws_rds_cluster.litellm.id
    engine_version = aws_rds_cluster.litellm.engine_version
  })
}

output "coder_cluster_endpoint" {
  description = "Aurora cluster writer endpoint for Coder"
  value       = aws_rds_cluster.coder.endpoint
}

output "coder_cluster_reader_endpoint" {
  description = "Aurora cluster reader endpoint for Coder"
  value       = aws_rds_cluster.coder.reader_endpoint
}

output "coder_cluster_port" {
  description = "Aurora cluster port for Coder"
  value       = aws_rds_cluster.coder.port
}

output "coder_db_secret_arn" {
  description = "ARN of Secrets Manager secret containing Coder DB credentials"
  value       = aws_secretsmanager_secret.coder_db.arn
}

output "litellm_cluster_endpoint" {
  description = "Aurora cluster writer endpoint for LiteLLM"
  value       = aws_rds_cluster.litellm.endpoint
}

output "litellm_cluster_reader_endpoint" {
  description = "Aurora cluster reader endpoint for LiteLLM"
  value       = aws_rds_cluster.litellm.reader_endpoint
}

output "litellm_cluster_port" {
  description = "Aurora cluster port for LiteLLM"
  value       = aws_rds_cluster.litellm.port
}

output "litellm_db_secret_arn" {
  description = "ARN of Secrets Manager secret containing LiteLLM DB credentials"
  value       = aws_secretsmanager_secret.litellm_db.arn
}
