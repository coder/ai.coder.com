# Cache ECR repository ARN pattern for reuse across policy statements
locals {
  ecr_repo_arn = "arn:aws:ecr:${data.aws_region.this.region}:${data.aws_caller_identity.this.account_id}:repository/*"
}

data "aws_iam_policy_document" "this" {
  statement {
    sid    = "ECRAuthToken"
    effect = "Allow"
    # GetAuthorizationToken requires wildcard resource per AWS API requirements
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid    = "ECRReadAccess"
    effect = "Allow"
    # Scoped to specific account repositories for least privilege
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer"
    ]
    resources = [local.ecr_repo_arn]
  }

  statement {
    sid    = "ECRWriteAccess"
    effect = "Allow"
    # Scoped to specific account repositories for least privilege
    actions = [
      "ecr:CompleteLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:InitiateLayerUpload",
      "ecr:BatchCheckLayerAvailability",
      "ecr:PutImage",
      "ecr:BatchGetImage",
      "ecr:DescribeRepositories"
    ]
    resources = [local.ecr_repo_arn]
  }
}