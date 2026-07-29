provider "aws" {
  profile = var.profile
  region  = var.region
}

data "aws_caller_identity" "this" {}

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

data "aws_iam_policy_document" "grafana-sts" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["grafana.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = ["${data.aws_caller_identity.this.account_id}"]
    }
    condition {
      test     = "StringLike"
      variable = "aws:SourceArn"
      values   = ["arn:aws:grafana:${var.region}:${data.aws_caller_identity.this.account_id}:/workspaces/*"]
    }
  }
}

locals {
  name = "coder-observe"
}

resource "aws_iam_role" "grafana" {
  name               = "${local.name}-grafana"
  path               = "/"
  assume_role_policy = data.aws_iam_policy_document.grafana-sts.json
}

data "aws_iam_policy_document" "grafana" {
  statement {
    effect = "Allow"
    actions = [
      "aps:ListWorkspaces",
      "aps:DescribeWorkspace",
      "aps:QueryMetrics",
      "aps:GetLabels",
      "aps:GetSeries",
      "aps:GetMetricMetadata"
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "policy" {
  name        = "${local.name}-grafana"
  description = "AWS Managed Grafana Policy"
  policy      = data.aws_iam_policy_document.grafana.json
}

resource "aws_iam_role_policy_attachment" "grafana" {

  for_each = {
    "${local.name}-grafana"         = aws_iam_policy.policy.arn
    "AmazonGrafanaCloudWatchAccess" = "arn:aws:iam::aws:policy/service-role/AmazonGrafanaCloudWatchAccess"
  }

  role       = aws_iam_role.grafana.name
  policy_arn = each.value
}

resource "aws_security_group" "grafana" {
  vpc_id      = data.aws_vpc.this.id
  name        = "${local.name}-grafana"
  description = "SG for Grafana - All Egress traffic"
  tags = {
    Name = "Customer-Managed AWS Managed Grafana"
  }
}

resource "aws_vpc_security_group_egress_rule" "grafana" {
  security_group_id = aws_security_group.grafana.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = -1
}

locals {
  # Root, Coder, Customer
  ous = ["r-4vw4", "ou-4vw4-avnmq38g", "ou-4vw4-2qki2hxj"]
}

resource "aws_grafana_workspace" "this" {

  name = local.name

  account_access_type      = "ORGANIZATION"
  organizational_units     = local.ous
  authentication_providers = ["AWS_SSO"]
  permission_type          = "CUSTOMER_MANAGED"
  region                   = var.region
  data_sources             = ["PROMETHEUS", "CLOUDWATCH"]
  grafana_version          = "10.4"
  role_arn                 = aws_iam_role.grafana.arn

  vpc_configuration {
    security_group_ids = [
      aws_security_group.grafana.id
    ]
    subnet_ids = toset(concat(
      data.aws_subnets.private.ids
    ))
  }
}

resource "aws_grafana_workspace_service_account" "admin" {
  name         = "admin"
  grafana_role = "ADMIN"
  workspace_id = aws_grafana_workspace.this.id
}

locals {
  rotation_days = 30
}

resource "time_rotating" "admin" {
  rotation_days = local.rotation_days
}

resource "random_pet" "token_name" {
  keepers = {
    time = time_rotating.admin.unix
  }
}

resource "aws_grafana_workspace_service_account_token" "admin" {
  name               = random_pet.token_name.id
  service_account_id = aws_grafana_workspace_service_account.admin.service_account_id
  seconds_to_live    = local.rotation_days * 24 * 60 * 60 # 2591999 # 30 days
  workspace_id       = aws_grafana_workspace.this.id

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_prometheus_workspace" "this" {
  alias = local.name
}

output "grafana_endpoint" {
  value = "https://${aws_grafana_workspace.this.endpoint}"
}

output "prometheus_endpoint" {
  value = aws_prometheus_workspace.this.prometheus_endpoint
}

output "aws_grafana_workspace_service_account_token" {
  value     = aws_grafana_workspace_service_account_token.admin.key
  sensitive = true
}