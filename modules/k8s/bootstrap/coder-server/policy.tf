locals {
  rds_db_name = split(".", var.db.url)[0]
}

data "aws_db_instance" "coder" {
  db_instance_identifier = local.rds_db_name
}

data "aws_iam_policy_document" "provisioner" {
  statement {
    effect = "Allow"
    actions = [
      "ec2:GetDefaultCreditSpecification",
      "ec2:DescribeIamInstanceProfileAssociations",
      "ec2:DescribeTags",
      "ec2:DescribeInstances",
      "ec2:DescribeInstanceTypes",
      "ec2:DescribeInstanceStatus",
      "ec2:CreateTags",
      "ec2:RunInstances",
      "ec2:DescribeInstanceCreditSpecifications",
      "ec2:DescribeImages",
      "ec2:ModifyDefaultCreditSpecification",
      "ec2:DescribeVolumes"
    ]
    resources = ["*"]
  }

  statement {
    effect = "Allow"
    actions = [
      "ec2:DescribeInstanceAttribute",
      "ec2:UnmonitorInstances",
      "ec2:TerminateInstances",
      "ec2:StartInstances",
      "ec2:StopInstances",
      "ec2:DeleteTags",
      "ec2:MonitorInstances",
      "ec2:CreateTags",
      "ec2:RunInstances",
      "ec2:ModifyInstanceAttribute",
      "ec2:ModifyInstanceCreditSpecification"
    ]
    resources = ["arn:aws:ec2:*:*:instance/*"]
  }
}

data "aws_iam_policy_document" "rds" {
  statement {
    effect    = "Allow"
    actions   = ["rds-db:connect"]
    resources = [
      "arn:aws:rds-db:${local.region}:${local.account_id}:dbuser:${data.aws_db_instance.coder.resource_id}/${var.db.username}"
    ]
  }
}