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

variable "path" {
  type    = string
  default = "/"
}

variable "tags" {
  type    = map(string)
  default = {}
}

variable "service_actions" {
  type    = list(string)
  default = []
}

variable "service_principals" {
  type    = list(string)
  default = []
}

variable "policy_arns" {
  type    = map(string)
  default = {}
}


data "aws_iam_policy_document" "sts" {
  statement {
    actions = var.service_actions
    principals {
      type        = "Service"
      identifiers = var.service_principals
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

resource "aws_iam_instance_profile" "this" {
  count       = contains(toset(var.service_principals), "ec2.amazonaws.com") ? 1 : 0
  name_prefix = "${var.name}-"
  role        = aws_iam_role.this.name
}

output "role_name" {
  value = aws_iam_role.this.name
}

output "role_arn" {
  value = aws_iam_role.this.arn
}

output "instance_profile_name" {
  value = try(aws_iam_instance_profile.this[0].id, "ADD EC2.AMAZONAWS.COM PRINCIPAL TO CREATE")
}