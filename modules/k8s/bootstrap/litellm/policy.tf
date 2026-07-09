locals {
    rds_db_name = split(".", var.db.endpoint)[0]
}

data "aws_db_instance" "litellm" {
  db_instance_identifier = local.rds_db_name
}

data "aws_iam_policy_document" "rds" {
  statement {
    effect    = "Allow"
    actions   = ["rds-db:connect"]
    resources = [
      "arn:aws:rds-db:${local.region}:${local.account_id}:dbuser:${data.aws_db_instance.litellm.resource_id}/${var.db.username}"
    ]
  }
}