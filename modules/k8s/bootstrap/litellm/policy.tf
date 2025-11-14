data "aws_iam_policy_document" "bedrock-policy" {
  statement {
    sid    = "AllowModelInvocation"
    effect = "Allow"
    actions = [
      "bedrock:InvokeModel",
      "bedrock:InvokeModelWithResponseStream"
    ]
    # Restricted to specific region and account because wildcards allow access to all Bedrock resources globally
    resources = [
      "arn:aws:bedrock:${var.aws_bedrock_region}:${data.aws_caller_identity.this.account_id}:inference-profile/*",
      "arn:aws:bedrock:${var.aws_bedrock_region}::foundation-model/*"
    ]
  }
  statement {
    sid    = "AllowListInferenceProfiles"
    effect = "Allow"
    actions = [
      "bedrock:ListInferenceProfiles"
    ]
    # ListInferenceProfiles requires wildcard resource
    resources = ["*"]
  }
}