data "aws_iam_policy_document" "this" {
  statement {
    sid = "LokiChunksBucket"
    effect = "Allow"
    actions = [
        "s3:PutObject",
        "s3:ListBucket",
        "s3:GetObject",
        "s3:DeleteObject"
    ]
    resources = [
        "arn:aws:s3:::${var.loki.s3.chunks_bucket}/*",
        "arn:aws:s3:::${var.loki.s3.chunks_bucket}"
    ]
  }

  statement {
    sid = "LokiRulerBucket"
    effect = "Allow"
    actions = [
        "s3:PutObject",
        "s3:ListBucket",
        "s3:GetObject",
        "s3:DeleteObject"
    ]
    resources = [
        "arn:aws:s3:::${var.loki.s3.ruler_bucket}/*",
        "arn:aws:s3:::${var.loki.s3.ruler_bucket}"
    ]
  }
}