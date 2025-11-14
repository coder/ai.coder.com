terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }
}

variable "name" {
  type = string
}

variable "cluster_name" {
  type = string
}

variable "path" {
  type    = string
  default = "/"
}

variable "tags" {
  type    = map(string)
  default = {}
}

variable "oidc_principals" {
  type    = map(list(string))
  default = {}
}

variable "policy_arns" {
  type    = map(string)
  default = {}
}

variable "cluster_create_access_entry" {
  type    = bool
  default = false
}

variable "cluster_policy_arns" {
  type    = map(string)
  default = {}
}

variable "cluster_access_type" {
  type    = string
  default = "STANDARD"
}

locals {
  # Extract OIDC provider path for readability because repeated string manipulation is hard to maintain
  oidc_provider_paths = {
    for arn, subjects in var.oidc_principals :
    arn => join("/", slice(split("/", arn), 1, length(split("/", arn))))
  }
}

data "aws_iam_policy_document" "sts" {
  dynamic "statement" {
    for_each = var.oidc_principals
    content {
      actions = ["sts:AssumeRoleWithWebIdentity"]
      principals {
        type        = "Federated"
        identifiers = [statement.key]
      }
      condition {
        test     = "StringLike"
        variable = "${local.oidc_provider_paths[statement.key]}:sub"
        values   = statement.value
      }
      condition {
        test     = "StringEquals"
        variable = "${local.oidc_provider_paths[statement.key]}:aud"
        values   = ["sts.amazonaws.com"]
      }
    }
  }
}

resource "aws_iam_role_policy_attachment" "this" {
  for_each   = var.policy_arns
  role       = aws_iam_role.this.name
  policy_arn = each.value
}

resource "aws_iam_role" "this" {
  name_prefix        = "${var.name}-"
  path               = var.path
  assume_role_policy = data.aws_iam_policy_document.sts.json
  tags               = var.tags
}

resource "aws_eks_access_entry" "this" {

  count = var.cluster_create_access_entry ? 1 : 0

  principal_arn = aws_iam_role.this.arn
  cluster_name  = var.cluster_name
  type          = var.cluster_access_type
}

resource "aws_eks_access_policy_association" "attach" {
  # Removed depends_on because for_each already handles conditional creation
  for_each = var.cluster_create_access_entry ? var.cluster_policy_arns : {}

  cluster_name  = var.cluster_name
  policy_arn    = each.value
  principal_arn = aws_iam_role.this.arn

  access_scope {
    type = "cluster"
  }

  # Policy association requires access entry to exist; for_each already handles conditional creation
  depends_on = [aws_eks_access_entry.this[0]]
}

output "role_name" {
  value = aws_iam_role.this.name
}

output "role_arn" {
  value = aws_iam_role.this.arn
}

output "access_entry_arn" {
  # Returns null when access entry not created because string fallback reduces type consistency
  value = try(aws_eks_access_entry.this[0].access_entry_arn, null)
}