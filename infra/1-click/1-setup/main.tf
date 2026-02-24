##
# Remote State Resources
##

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

data "aws_region" "this" {}

locals {
  apex_domain            = join(".", slice(split(".", var.domain_name), length(split(".", var.domain_name)) - 2, length(split(".", var.domain_name))))
  normalized_domain_name = split(".", var.domain_name)[0]
  formatted_name         = "${var.name}-${local.normalized_domain_name}"
}

data "aws_vpc" "this" {
  tags = {
    "Name" = local.formatted_name
  }
}

data "aws_s3_bucket" "loki" {
  bucket = "${local.formatted_name}-grafana"
}

data "aws_db_instance" "coder" {
  db_instance_identifier = "${local.formatted_name}-coder"
}

data "aws_db_instance" "grafana" {
  db_instance_identifier = "${local.formatted_name}-grafana"
}

data "aws_security_group" "coder" {
  name   = "${local.formatted_name}-pgsql"
  vpc_id = data.aws_vpc.this.id
}

data "aws_eks_cluster" "coder" {
  name   = local.formatted_name
  region = var.region
}

data "aws_eks_cluster_auth" "coder" {
  name   = local.formatted_name
  region = var.region
}

data "aws_iam_openid_connect_provider" "coder" {
  url = data.aws_eks_cluster.coder.identity[0].oidc[0].issuer
}