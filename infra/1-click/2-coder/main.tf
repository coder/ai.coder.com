##
# Global Inputs + Providers
##

locals {
  formatted_name         = "${var.name}-${local.normalized_domain_name}"
  normalized_domain_name = split(".", var.domain_name)[0]
}

provider "aws" {
  region  = var.region
  profile = var.profile
}

data "aws_region" "this" {}

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

##
# Coder MUST be in a reachable state by now
##

data "aws_eip" "coder" {
  region = var.region
  tags = {
    Name = "${local.formatted_name}-coder-0"
  }
}

data "http" "login" {
  url    = "http://${data.aws_eip.coder.public_ip}/api/v2/users/login"
  method = "POST"
  request_headers = {
    Host   = var.domain_name
    Accept = "application/json"
  }
  request_body = jsonencode({
    email    = var.coder_admin_email
    password = var.coder_admin_password
  })
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

provider "coderd" {
  url   = "http://${data.aws_eip.coder.public_ip}"
  token = jsondecode(data.http.login.response_body).session_token
}