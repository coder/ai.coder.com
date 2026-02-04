terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.46"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 3.1.1"
    }
    kubernetes = {
      source = "hashicorp/kubernetes"
    }
    external = {
      source = "hashicorp/external"
    }
    http = {
      source = "hashicorp/http"
    }
    dns = {
      source = "hashicorp/dns"
    }
    cloudflare = {
      source = "cloudflare/cloudflare"
    }
  }
}

##
# Remote State Resources
##

data "aws_vpc" "this" {
  tags = {
    "Name" = "${var.name}-${local.normalized_domain_name}"
  }
}

data "aws_s3_bucket" "loki" {
  bucket = "${var.name}-${local.normalized_domain_name}-grafana"
}

data "aws_db_instance" "coder" {
  db_instance_identifier = "${var.name}-${local.normalized_domain_name}-coder"
}

data "aws_db_instance" "grafana" {
  db_instance_identifier = "${var.name}-${local.normalized_domain_name}-grafana"
}

data "aws_security_group" "coder" {
  name   = "${var.name}-${local.normalized_domain_name}-pgsql"
  vpc_id = data.aws_vpc.this.id
}

data "aws_eks_cluster" "coder" {
  name = "${var.name}-${local.normalized_domain_name}"
}

data "aws_eks_cluster_auth" "coder" {
  name = "${var.name}-${local.normalized_domain_name}"
}

data "aws_iam_openid_connect_provider" "coder" {
  url = data.aws_eks_cluster.coder.identity[0].oidc[0].issuer
}

##
# Global Inputs + Providers
##

variable "region" {
  description = "The AWS region of the deployment."
  type        = string
  default     = "us-east-2"
}

variable "name" {
  description = "Name for created resources and tag prefix."
  type        = string
  default     = "coder"
}

variable "profile" {
  type    = string
  default = "default"
}

variable "domain_name" {
  type = string
}

provider "aws" {
  region  = var.region
  profile = var.profile
}

provider "helm" {
  kubernetes = {
    host                   = data.aws_eks_cluster.coder.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.coder.certificate_authority[0].data)
    token                  = data.aws_eks_cluster_auth.coder.token
  }
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.coder.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.coder.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.coder.token
}

variable "auto_set_record" {
  description = "Set if you don't want to use external-dns, but still want to automatically set the domain name."
  type = object({
    use_cf = bool
    cf_token = optional(string, "")
    use_r53 = bool
  })
  default = {
    use_cf = false
    cf_token = ""
    use_r53 = true
  }
  sensitive = true

  validation {
    condition = !(var.auto_set_record.use_cf && var.auto_set_record.use_r53)
    error_message = "'use_cf' and 'use_r53' cannot both be true."
  }

  validation {
    condition = !(var.auto_set_record.use_cf && var.auto_set_record.cf_token == "")
    error_message = "'cf_token' cannot be unset when 'use_cf' is true."
  }
}

provider "cloudflare" {
  api_token = var.auto_set_record.cf_token
}

data "aws_region" "this" {}

locals {
  normalized_domain_name = split(".", var.domain_name)[0]
  apex_domain = join(".", slice(split(".", var.domain_name), length(split(".", var.domain_name))-2, length(split(".", var.domain_name))))
}

##
# Fetch DNS Zone
##

data "aws_route53_zone" "coder" {
  count = nonsensitive(var.auto_set_record.use_r53) ? 1 : 0
  name = local.apex_domain
}

data "cloudflare_zone" "coder" {
  count = nonsensitive(var.auto_set_record.use_cf) ? 1 : 0
  filter = {
    name = local.apex_domain
  }
}

##
# Coder DNS Record Setup
##

resource "aws_route53_record" "coder-primary" {
  count = nonsensitive(var.auto_set_record.use_r53) ? 1 : 0
  zone_id = data.aws_route53_zone.coder[0].zone_id
  name    = var.domain_name
  type    = "A"
  ttl     = "30"
  records = aws_eip.coder.*.public_ip
}

resource "aws_route53_record" "coder-wildcard" {
  count = nonsensitive(var.auto_set_record.use_r53) ? 1 : 0
  zone_id = data.aws_route53_zone.coder[0].zone_id
  name    = "*.${var.domain_name}"
  type    = "A"
  ttl     = "60"
  records = aws_eip.coder.*.public_ip
}

resource "cloudflare_dns_record" "coder-primary" {

  for_each = nonsensitive(var.auto_set_record.use_cf) ? toset(aws_eip.coder.*.public_ip) : toset([])

  zone_id = data.cloudflare_zone.coder[0].id
  name = var.domain_name
  ttl = 1
  type = "A"
  comment = ""
  content = each.value
  proxied = true
}

resource "cloudflare_dns_record" "coder-wildcard" {

  for_each = nonsensitive(var.auto_set_record.use_cf) ? toset(aws_eip.coder.*.public_ip) : toset([])

  zone_id = data.cloudflare_zone.coder[0].id
  name = "*.${var.domain_name}"
  ttl = 1
  type = "A"
  comment = ""
  content = each.value
  proxied = true
}

##
# Grafana DNS Record Setup
##

resource "aws_route53_record" "grafana-primary" {
  count = nonsensitive(var.auto_set_record.use_r53) ? 1 : 0
  zone_id = data.aws_route53_zone.coder[0].zone_id
  name    = "grafana.${var.domain_name}"
  type    = "A"
  ttl     = "30"
  records = aws_eip.grafana.*.public_ip
}

resource "aws_route53_record" "grafana-wildcard" {
  count = nonsensitive(var.auto_set_record.use_r53) ? 1 : 0
  zone_id = data.aws_route53_zone.coder[0].zone_id
  name    = "*.grafana.${var.domain_name}"
  type    = "A"
  ttl     = "60"
  records = aws_eip.grafana.*.public_ip
}

resource "cloudflare_dns_record" "grafana-primary" {

  for_each = nonsensitive(var.auto_set_record.use_cf) ? toset(aws_eip.grafana.*.public_ip) : toset([])

  zone_id = data.cloudflare_zone.coder[0].id
  name = "grafana.${var.domain_name}"
  ttl = 1
  type = "A"
  comment = ""
  content = each.value
  proxied = true
}

resource "cloudflare_dns_record" "grafana-wildcard" {

  for_each = nonsensitive(var.auto_set_record.use_cf) ? toset(aws_eip.grafana.*.public_ip) : toset([])

  zone_id = data.cloudflare_zone.coder[0].id
  name = "*.grafana.${var.domain_name}"
  ttl = 1
  type = "A"
  comment = ""
  content = each.value
  proxied = true
}
