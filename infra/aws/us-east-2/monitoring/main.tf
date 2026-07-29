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
  admin_iam_identity_ids = [
    "24c85468-90e1-70c7-3498-bc5695b7c6f0", # Jullian
  ]
}

data "aws_ssoadmin_instances" "this" {
  region = "us-east-1"
}

data "aws_identitystore_group" "aws_administrator" {
  identity_store_id = one(data.aws_ssoadmin_instances.this.identity_store_ids)
  region            = "us-east-1"

  alternate_identifier {
    unique_attribute {
      attribute_path  = "DisplayName"
      attribute_value = "CoderCSAWSAdmin"
    }
  }
}

data "aws_identitystore_group_memberships" "aws_admins" {
  identity_store_id = one(data.aws_ssoadmin_instances.this.identity_store_ids)
  region            = "us-east-1"
  group_id          = data.aws_identitystore_group.aws_administrator.group_id
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

data "aws_identitystore_user" "admin" {
  region            = "us-east-1"
  identity_store_id = one(data.aws_ssoadmin_instances.this.identity_store_ids)
  alternate_identifier {
    unique_attribute {
      attribute_path  = "UserName"
      attribute_value = "jullian@coder.com"
    }
  }
}

data "aws_identitystore_users" "viewers" {
  region            = "us-east-1"
  identity_store_id = one(data.aws_ssoadmin_instances.this.identity_store_ids)
}


locals {
  admins = [data.aws_identitystore_user.admin.user_id]
}

resource "aws_grafana_role_association" "admins" {
  role = "ADMIN"
  # user_ids     = [data.aws_identitystore_user.admin.user_id]
  user_ids     = [for i in data.aws_identitystore_users.viewers.users : i.user_id]
  group_ids    = [data.aws_identitystore_group.aws_administrator.group_id]
  workspace_id = aws_grafana_workspace.this.id
}


# resource "aws_grafana_role_association" "viewer" {
#   role         = "VIEWER"
#   user_ids     = [for i in data.aws_identitystore_users.viewers.users : i.user_id if contains(local.admins, i.user_id) ]
#   group_ids    = [] # [data.aws_identitystore_group.aws_administrator.group_id]
#   workspace_id = aws_grafana_workspace.this.id
# }

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

# resource "aws_grafana_workspace_service_account" "viewer" {
#   name         = "viewer"
#   grafana_role = "VIEWER"
#   workspace_id = aws_grafana_workspace.this.id
# }

resource "aws_prometheus_workspace" "this" {
  alias = local.name
}

# resource "aws_prometheus_rule_group_namespace" "coder_alerts" {
#   name         = "coder-alerts"
#   workspace_id = aws_prometheus_workspace.coder.id
#   data         = file("${path.module}/alert-rules.yaml")
# }

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