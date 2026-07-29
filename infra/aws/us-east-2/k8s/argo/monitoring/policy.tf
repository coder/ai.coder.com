data "aws_iam_policy_document" "loki" {
  statement {
    sid    = "LokiChunksBucket"
    effect = "Allow"
    actions = [
      "s3:PutObject",
      "s3:ListBucket",
      "s3:GetObject",
      "s3:DeleteObject"
    ]
    resources = [
      "arn:aws:s3:::${data.aws_s3_bucket.loki.id}/*",
      "arn:aws:s3:::${data.aws_s3_bucket.loki.id}"
    ]
  }

  statement {
    sid    = "LokiRulerBucket"
    effect = "Allow"
    actions = [
      "s3:PutObject",
      "s3:ListBucket",
      "s3:GetObject",
      "s3:DeleteObject"
    ]
    resources = [
      "arn:aws:s3:::${data.aws_s3_bucket.loki.id}/*",
      "arn:aws:s3:::${data.aws_s3_bucket.loki.id}"
    ]
  }
}