##
# Bucket Infrastructure
##

##
# Loki Inputs
##

variable "loki_s3_bucket_name" {
  type = string
  default = ""
}

variable "loki_s3_bucket_tags" {
  type    = map(string)
  default = {}
}

resource "random_string" "bucket" {
  keepers = {
    static = "true"
  }
  length           = 16
  special          = false
  upper = false
  lower = true
}

resource "aws_s3_bucket" "loki" {
  bucket = var.loki_s3_bucket_name == "" ? "granafa-logs-${random_string.bucket.result}" : var.loki_s3_bucket_name
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