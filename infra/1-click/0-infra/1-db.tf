##
# Database Infrastructure
##

resource "aws_security_group" "postgres" {
  vpc_id      = module.vpc.vpc_id
  name        = "${local.formatted_name}-pgsql"
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
  name       = "${local.formatted_name}-coder"
  subnet_ids = module.vpc.private_subnets

  tags = {
    Name = "${local.formatted_name}-coder"
  }
}

resource "time_static" "coder_snapshot" {
  triggers = {
    run_on_ip_change = "${local.formatted_name}-coder"
  }
}

resource "aws_db_instance" "coder" {
  identifier                = "${local.formatted_name}-coder"
  instance_class            = "db.t4g.medium"
  allocated_storage         = 50
  engine                    = "postgres"
  engine_version            = "15.12"
  username                  = var.coder_username
  password                  = var.coder_password
  db_name                   = "coder"
  db_subnet_group_name      = aws_db_subnet_group.coder.name
  vpc_security_group_ids    = [aws_security_group.postgres.id]
  publicly_accessible       = false
  snapshot_identifier       = null
  skip_final_snapshot       = false
  final_snapshot_identifier = "coder-${replace(time_static.coder_snapshot.rfc3339, ":", "-")}"

  tags = {
    Name = "${local.formatted_name}-coder"
  }
  lifecycle {
    ignore_changes = [
      snapshot_identifier
    ]
  }
}

resource "time_static" "grafana_snapshot" {
  triggers = {
    run_on_ip_change = "${local.formatted_name}-grafana"
  }
}

resource "aws_db_instance" "grafana" {
  identifier                = "${local.formatted_name}-grafana"
  instance_class            = "db.t4g.medium"
  allocated_storage         = 50
  engine                    = "postgres"
  engine_version            = "15.12"
  username                  = var.grafana_username
  password                  = var.grafana_password
  db_name                   = "grafana"
  db_subnet_group_name      = aws_db_subnet_group.coder.name
  vpc_security_group_ids    = [aws_security_group.postgres.id]
  publicly_accessible       = false
  snapshot_identifier       = null
  skip_final_snapshot       = false
  final_snapshot_identifier = "grafana-${replace(time_static.coder_snapshot.rfc3339, ":", "-")}"

  tags = {
    Name = "${local.formatted_name}-grafana"
  }
  lifecycle {
    ignore_changes = [
      snapshot_identifier
    ]
  }
}