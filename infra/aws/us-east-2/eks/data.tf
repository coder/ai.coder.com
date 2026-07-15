data "aws_caller_identity" "me" {}

data "aws_vpc" "this" {
  tags = {
    Name = var.vpc_name
  }
}

data "aws_subnets" "public" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.this.id]
  }

  tags = {
    Name = "*${var.public_subnet_suffix}*"
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

data "aws_iam_policy_document" "ecr-mirror" {

  statement {
    effect    = "Allow"
    actions   = ["ecr:CreateRepository"]
    resources = ["*"]
  }

  statement {
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    effect = "Allow"
    actions = [
      "ecr:BatchImportUpstreamImage",
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer"
    ]
    resources = ["arn:aws:ecr:${var.region}:${data.aws_caller_identity.me.account_id}:repository/cache/*"]
  }
}