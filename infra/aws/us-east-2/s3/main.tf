terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.46"
    }
  }
  backend "s3" {}
}

##
# AWS Provider Inputs
##

variable "region" {
  description = "The aws region for database deployment"
  type        = string
}

variable "profile" {
  type = string
}

provider "aws" {
  region  = var.region
  profile = var.profile
}

##
# Loki Inputs
##

variable "loki_s3_bucket_name" {
  type = string
}

variable "loki_s3_bucket_tags" {
  type    = map(string)
  default = {}
}

resource "aws_s3_bucket" "loki" {
  bucket = var.loki_s3_bucket_name
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