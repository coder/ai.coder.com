data "aws_iam_policy_document" "this" {

  statement {
    effect    = "Allow"
    actions   = ["route53:ListHostedZones"]
    resources = ["*"]
  }

  statement {
      effect = "Allow"
      actions = [
        "route53:ChangeResourceRecordSets",
        "route53:ListResourceRecordSets",
        "route53:ListTagsForResources"
      ]
      resources = [
        "arn:aws:route53:::hostedzone/*"
      ]
  }
}