terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

variable "cluster_region" {
  description = "AWS region for ACM certificate"
  type        = string
  default     = "us-west-2"
}

variable "cluster_profile" {
  description = "AWS profile"
  type        = string
  default     = "default"
}

variable "domain_name" {
  description = "Domain name for Coder"
  type        = string
  default     = "coderdemo.io"
}

variable "hosted_zone_id" {
  description = "Route 53 Hosted Zone ID"
  type        = string
}

provider "aws" {
  region  = var.cluster_region
  profile = var.cluster_profile
  alias   = "acm"
}

# Provider for Route 53 (may be in different account)
provider "aws" {
  region  = var.cluster_region
  profile = var.cluster_profile
  alias   = "route53"
}

# ACM Certificate for Coder with wildcard
resource "aws_acm_certificate" "coder" {
  provider          = aws.acm
  domain_name       = var.domain_name
  validation_method = "DNS"

  subject_alternative_names = [
    "*.${var.domain_name}"
  ]

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name        = "coder-certificate"
    Environment = "production"
    ManagedBy   = "terraform"
    Region      = "us-west-2"
  }
}

# Route 53 validation records
resource "aws_route53_record" "cert_validation" {
  provider = aws.route53
  for_each = {
    for dvo in aws_acm_certificate.coder.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = var.hosted_zone_id
}

# Wait for certificate validation
resource "aws_acm_certificate_validation" "coder" {
  provider                = aws.acm
  certificate_arn         = aws_acm_certificate.coder.arn
  validation_record_fqdns = [for record in aws_route53_record.cert_validation : record.fqdn]
}

# Outputs
output "certificate_arn" {
  description = "ARN of the validated ACM certificate"
  value       = aws_acm_certificate_validation.coder.certificate_arn
}

output "domain_name" {
  description = "Domain name for Coder"
  value       = var.domain_name
}

output "validation_status" {
  description = "Certificate validation status"
  value       = "Certificate validated and ready to use"
}
