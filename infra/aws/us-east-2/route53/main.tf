terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.0"
    }
  }
}

variable "cluster_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-2"
}

variable "cluster_profile" {
  description = "AWS profile"
  type        = string
  default     = "default"
}

variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
}

variable "domain_name" {
  description = "Domain name for Coder"
  type        = string
  default     = ""
}

variable "hosted_zone_id" {
  description = "Route 53 Hosted Zone ID (provide via tfvars)"
  type        = string
}

variable "coder_service_name" {
  description = "Coder service name in Kubernetes"
  type        = string
  default     = "coder"
}

variable "coder_namespace" {
  description = "Coder namespace in Kubernetes"
  type        = string
  default     = "coder"
}

variable "set_identifier" {
  description = "Unique identifier for this routing policy record"
  type        = string
  default     = "us-east-2"
}

variable "health_check_enabled" {
  description = "Enable Route 53 health checks"
  type        = bool
  default     = true
}

variable "health_check_path" {
  description = "Path for health checks"
  type        = string
  default     = "/api/v2/buildinfo"
}

provider "aws" {
  region  = var.cluster_region
  profile = var.cluster_profile
}

data "aws_eks_cluster" "this" {
  name = var.cluster_name
}

data "aws_eks_cluster_auth" "this" {
  name = var.cluster_name
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.this.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.this.token
}

# Get the NLB hostname from the Kubernetes service
data "kubernetes_service" "coder" {
  metadata {
    name      = var.coder_service_name
    namespace = var.coder_namespace
  }
}

# Extract the NLB details
locals {
  nlb_hostname = try(data.kubernetes_service.coder.status[0].load_balancer[0].ingress[0].hostname, "")
}

# Get NLB by tags (AWS Load Balancer Controller tags the NLB)
data "aws_lb" "coder_nlb" {
  tags = {
    "service.k8s.aws/stack" = "${var.coder_namespace}/${var.coder_service_name}"
  }
}

# Health check for the NLB endpoint
resource "aws_route53_health_check" "coder" {
  count             = var.health_check_enabled ? 1 : 0
  type              = "HTTPS"
  resource_path     = var.health_check_path
  fqdn              = var.domain_name
  port              = 443
  request_interval  = 30
  failure_threshold = 3
  measure_latency   = true

  tags = {
    Name        = "coder-${var.set_identifier}"
    Region      = var.cluster_region
    Environment = "production"
    ManagedBy   = "terraform"
  }
}

# Latency-based routing record for the main domain
resource "aws_route53_record" "coder_latency" {
  zone_id         = var.hosted_zone_id
  name            = var.domain_name
  type            = "A"
  set_identifier  = var.set_identifier
  allow_overwrite = true

  alias {
    name                   = local.nlb_hostname
    zone_id                = data.aws_lb.coder_nlb.zone_id
    evaluate_target_health = true
  }

  latency_routing_policy {
    region = var.cluster_region
  }

  health_check_id = var.health_check_enabled ? aws_route53_health_check.coder[0].id : null
}

# Latency-based routing record for wildcard subdomains
resource "aws_route53_record" "coder_wildcard_latency" {
  zone_id         = var.hosted_zone_id
  name            = "*.${var.domain_name}"
  type            = "A"
  set_identifier  = var.set_identifier
  allow_overwrite = true

  alias {
    name                   = local.nlb_hostname
    zone_id                = data.aws_lb.coder_nlb.zone_id
    evaluate_target_health = true
  }

  latency_routing_policy {
    region = var.cluster_region
  }

  health_check_id = var.health_check_enabled ? aws_route53_health_check.coder[0].id : null
}

# Region-specific subdomain for manual region selection
resource "aws_route53_record" "coder_region_specific" {
  zone_id = var.hosted_zone_id
  name    = "${var.set_identifier}.${var.domain_name}"
  type    = "A"

  alias {
    name                   = local.nlb_hostname
    zone_id                = data.aws_lb.coder_nlb.zone_id
    evaluate_target_health = true
  }
}

# Wildcard for region-specific subdomain (for workspace apps)
resource "aws_route53_record" "coder_region_specific_wildcard" {
  zone_id = var.hosted_zone_id
  name    = "*.${var.set_identifier}.${var.domain_name}"
  type    = "A"

  alias {
    name                   = local.nlb_hostname
    zone_id                = data.aws_lb.coder_nlb.zone_id
    evaluate_target_health = true
  }
}

# Outputs
output "nlb_hostname" {
  description = "Network Load Balancer hostname"
  value       = local.nlb_hostname
}

output "nlb_zone_id" {
  description = "Network Load Balancer Route 53 zone ID"
  value       = data.aws_lb.coder_nlb.zone_id
}

output "health_check_id" {
  description = "Route 53 health check ID"
  value       = var.health_check_enabled ? aws_route53_health_check.coder[0].id : null
}

output "route53_record_fqdn" {
  description = "Fully qualified domain name of the Route 53 record"
  value       = aws_route53_record.coder_latency.fqdn
}
