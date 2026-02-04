##
# Bucket Infrastructure
##

##
# Loki Inputs
##

variable "loki_s3_bucket_tags" {
  type    = map(string)
  default = {}
}

resource "aws_s3_bucket" "loki" {
  bucket = "${var.name}-${local.normalized_domain_name}-grafana"
  tags   = var.loki_s3_bucket_tags
}

resource "aws_s3_bucket_lifecycle_configuration" "loki" {
  bucket = aws_s3_bucket.loki.id

  rule {
    id = "logs"

    filter {} # Target all objects in bucket.

    expiration {
      days = 365
    }

    status = "Enabled"
  }
}