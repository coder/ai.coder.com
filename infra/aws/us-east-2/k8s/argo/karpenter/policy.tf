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

resource "aws_iam_policy" "ecr-mirror" {
  name_prefix = "ecr-mirror"
  description = "Allows ECR pull-through cache automation including repository creation"
  path        = "/${var.region}/kptr/"
  policy      = data.aws_iam_policy_document.ecr-mirror.json
}

data "aws_iam_policy_document" "sts" {
  statement {
    effect    = "Allow"
    actions   = ["sts:*"]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "sts" {
  name_prefix = "${var.cluster_name}-sts-"
  path        = "/${var.cluster_name}/${var.region}/${local.std_karpenter_format}/"
  description = "Assume Role Policy"
  policy      = data.aws_iam_policy_document.sts.json
}

data "aws_iam_policy_document" "kptr_ctrl_assume_role_policy" {
  statement {
    effect = "Allow"

    principals {
      type        = "Federated"
      identifiers = [data.aws_iam_openid_connect_provider.this.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.cluster_oidc_provider}:sub"
      values   = ["system:serviceaccount:karpenter:karpenter"]
    }

    # https://aws.amazon.com/premiumsupport/knowledge-center/eks-troubleshoot-oidc-and-irsa/?nc1=h_ls
    condition {
      test     = "StringEquals"
      variable = "${local.cluster_oidc_provider}:aud"
      values   = ["sts.amazonaws.com"]
    }

    actions = ["sts:AssumeRoleWithWebIdentity"]
  }
}