data "aws_iam_policy_document" "bedrock" {
  statement {
    effect = "Allow"

    actions = [
      "bedrock:CallWithBearerToken",
      "bedrock:TagResource",
      "bedrock:UntagResource",
    ]

    resources = ["*"]
  }

  dynamic "statement" {
    for_each = length(var.aws_bedrock_allowed_models) != 0 ? [1] : []
    content {
      effect = "Allow"

      actions = [
        "bedrock:InvokeModel",
        "bedrock:InvokeModelWithResponseStream",
      ]

      resources = var.aws_bedrock_allowed_models
    }
  }

  statement {
    effect = "Allow"

    actions = [
      "kms:DescribeKey",
    ]

    resources = [
      "arn:*:kms:*:::*",
    ]
  }

  statement {
    effect = "Allow"

    actions = [
      "bedrock-mantle:CallWithBearerToken"
    ]

    resources = ["*"]
  }
}

data "aws_iam_policy_document" "assume-role" {
  statement {
    effect = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type = "AWS"
      identifiers = [
        "arn:aws:iam::${data.aws_caller_identity.this.account_id}:root"
      ]
    }

    condition {
      test     = "StringLike"
      variable = "aws:PrincipalArn"
      values = [
        "arn:aws:iam::${data.aws_caller_identity.this.account_id}:role/aienv/us-east-2/coder-srv-*"
      ]
    }

  }
}