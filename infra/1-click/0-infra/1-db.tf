##
# Database Infrastructure
## 

variable "coder_username" {
  description = "Coder DB's username."
  type        = string
  default     = "coder"
}

variable "coder_password" {
  description = "Coder DB's password."
  type        = string
  sensitive   = true
  default     = "th1s1sn0tas3cur3pass0wrd"
}

variable "litellm_username" {
  description = "LiteLLM DB's username."
  type        = string
  default =   "litellm"
}

variable "litellm_password" {
  description = "LiteLLM DB's password."
  type        = string
  sensitive   = true
  default     = "th1s1sn0tas3cur3pass0wrd"
}

variable "grafana_username" {
  description = "Grafana DB's username."
  type        = string
  default = "grafana"
}

variable "grafana_password" {
  description = "Grafana DB's password."
  type        = string
  sensitive   = true
  default     = "th1s1sn0tas3cur3pass0wrd"
}

resource "aws_security_group" "postgres" {
  vpc_id      = module.vpc.vpc_id
  name        = "${var.name}-${local.normalized_domain_name}-pgsql"
  description = "security group for postgres all egress traffic"
  tags = {
    Name = "PostgreSQL"
  }
}

resource "aws_vpc_security_group_ingress_rule" "postgres" {
  security_group_id = aws_security_group.postgres.id
  cidr_ipv4         = module.vpc.vpc_cidr_block
  ip_protocol       = "tcp"
  from_port         = 5432
  to_port           = 5432
}

resource "aws_vpc_security_group_egress_rule" "postgres" {
  security_group_id = aws_security_group.postgres.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = -1
}

resource "aws_db_subnet_group" "coder" {
  name       = "${var.name}-${local.normalized_domain_name}-coder"
  subnet_ids = local.private_subnet_ids

  tags = {
    Name = "${var.name}-${local.normalized_domain_name}-coder"
  }
}

resource "aws_db_instance" "coder" {
  identifier        = "${var.name}-${local.normalized_domain_name}-coder"
  instance_class    = "db.t4g.large"
  allocated_storage = 50
  engine            = "postgres"
  engine_version    = "15.12"
  # backup_retention_period = 7
  username                  = var.coder_username
  password                  = var.coder_password
  db_name                   = "coder"
  db_subnet_group_name      = aws_db_subnet_group.coder.name
  vpc_security_group_ids    = [aws_security_group.postgres.id]
  publicly_accessible       = false
  skip_final_snapshot       = true
  # final_snapshot_identifier = "coder-final"

  tags = {
    Name = "coder"
  }
  lifecycle {
    ignore_changes = [
      snapshot_identifier
    ]
  }
}

resource "aws_db_instance" "litellm" {
  identifier                = "${var.name}-${local.normalized_domain_name}-litellm"
  instance_class            = "db.t4g.medium"
  allocated_storage         = 50
  engine                    = "postgres"
  engine_version            = "15.12"
  username                  = var.litellm_username
  password                  = var.litellm_password
  db_name                   = "litellm"
  db_subnet_group_name      = aws_db_subnet_group.coder.name
  vpc_security_group_ids    = [aws_security_group.postgres.id]
  publicly_accessible       = false
  skip_final_snapshot       = true
  # final_snapshot_identifier = "litellm-final"

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
  identifier                = "${var.name}-${local.normalized_domain_name}-grafana"
  instance_class            = "db.t4g.large"
  allocated_storage         = 50
  engine                    = "postgres"
  engine_version            = "15.12"
  username                  = var.grafana_username
  password                  = var.grafana_password
  db_name                   = "grafana"
  db_subnet_group_name      = aws_db_subnet_group.coder.name
  vpc_security_group_ids    = [aws_security_group.postgres.id]
  publicly_accessible       = false
  skip_final_snapshot       = true
  # final_snapshot_identifier = "grafana-final"

  tags = {
    Name = "grafana"
  }
  lifecycle {
    ignore_changes = [
      snapshot_identifier
    ]
  }
}