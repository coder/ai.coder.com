##
# Coder Template Push
##

data "coderd_organization" "default" {
  is_default = true
}

##
# Standalone Kubernetes Template
##

data "archive_file" "k8s-default" {
  type        = "zip"
  excludes    = ["${path.module}/templates/kubernetes/.terraform"]
  source_dir  = "${path.module}/templates/kubernetes"
  output_path = "${path.module}/templates/kubernetes.zip"
}

resource "time_static" "k8s-default" {
  triggers = {
    run_on_ip_changes = data.aws_eip.coder.private_ip
    run_on_checksum   = "${data.archive_file.k8s-default.id}"
  }
}

resource "coderd_template" "k8s-default" {

  depends_on = [module.coder-ext-prov]

  name            = "kubernetes"
  organization_id = data.coderd_organization.default.id
  display_name    = "Kubernetes (Deployment)"
  description     = "Provision Kubernetes Deployments as Coder workspaces"
  icon            = "https://${var.domain_name}/icon/k8s.png"
  versions = [
    {
      name        = "stable-${formatdate("YYYY-MM-DD_hh-mm-ss", time_static.k8s-default.rfc3339)}"
      description = "The stable version of the template."
      directory   = "${path.module}/templates/kubernetes"
      active      = true
      tf_vars = [{
        name  = "namespace"
        value = "coder"
        }, {
        name  = "use_kubeconfig"
        value = tostring(false)
        }, {
        name  = "host_ip"
        value = data.aws_eip.coder.private_ip
      }]
    }
  ]
}

##
# Claude-Code Kubernetes Template
##

##
# NOTICE: This template requires a Premium license as it includes the following:
# - AI Bridge
#
# NOTE: AI Boundary's will not work in EKS Auto Mode.
##

data "archive_file" "k8s-claude" {

  count = var.coder_license != "" && length(module.coder-ext-prov) > 0 ? 1 : 0

  type        = "zip"
  excludes    = ["${path.module}/templates/kubernetes-claude/.terraform"]
  source_dir  = "${path.module}/templates/kubernetes-claude"
  output_path = "${path.module}/templates/kubernetes-claude.zip"
}

resource "time_static" "k8s-claude" {

  count = var.coder_license != "" && length(module.coder-ext-prov) > 0 ? 1 : 0

  triggers = {
    run_on_ip_changes = data.aws_eip.coder.private_ip
    run_on_checksum   = "${data.archive_file.k8s-claude[0].id}"
  }
}

resource "coderd_template" "k8s-claude" {

  count = var.coder_license != "" && length(module.coder-ext-prov) > 0 ? 1 : 0

  name            = "kubernetes-claude"
  organization_id = data.coderd_organization.default.id
  display_name    = "Claude Code on Coder"
  description     = "Provision a Kubernetes Deployments with Claude installed."
  icon            = "https://${var.domain_name}/icon/claude.svg"
  versions = [
    {
      name        = "stable-${formatdate("YYYY-MM-DD_hh-mm-ss", time_static.k8s-claude[0].rfc3339)}"
      description = "The stable version of the template."
      directory   = "${path.module}/templates/kubernetes-claude"
      active      = true
      tf_vars = [{
        name  = "namespace"
        value = "coder"
        }, {
        name  = "use_kubeconfig"
        value = tostring(false)
        }, {
        name  = "host_ip"
        value = data.aws_eip.coder.private_ip
      }]
    }
  ]
}

##
# AWS EC2 Linux
##

data "archive_file" "aws-linux" {
  type        = "zip"
  excludes    = ["${path.module}/templates/aws-linux/.terraform"]
  source_dir  = "${path.module}/templates/aws-linux"
  output_path = "${path.module}/templates/aws-linux.zip"
}

resource "time_static" "aws-linux" {
  triggers = {
    run_on_checksum = "${data.archive_file.aws-linux.id}"
  }
}

resource "coderd_template" "aws-linux" {

  depends_on = [module.coder-ext-prov]

  name            = "aws-linux"
  organization_id = data.coderd_organization.default.id
  display_name    = "AWS EC2 (Linux)"
  description     = "Provision an AWS EC2 Linux VM."
  icon            = "https://${var.domain_name}/icon/aws.svg"
  versions = [
    {
      name        = "stable-${formatdate("YYYY-MM-DD_hh-mm-ss", time_static.aws-linux.rfc3339)}"
      description = "The stable version of the template."
      directory   = "${path.module}/templates/aws-linux"
      active      = true
    }
  ]
}

##
# AWS EC2 Windows
##

data "archive_file" "aws-windows" {
  type        = "zip"
  excludes    = ["${path.module}/templates/aws-windows/.terraform"]
  source_dir  = "${path.module}/templates/aws-windows"
  output_path = "${path.module}/templates/aws-windows.zip"
}

resource "time_static" "aws-windows" {
  triggers = {
    run_on_checksum = "${data.archive_file.aws-windows.id}"
  }
}

resource "coderd_template" "aws-windows" {

  depends_on = [module.coder-ext-prov]

  name            = "aws-windows"
  organization_id = data.coderd_organization.default.id
  display_name    = "AWS EC2 (Windows)"
  description     = "Provision an AWS EC2 Windows VM."
  icon            = "https://${var.domain_name}/icon/windows.svg"
  versions = [
    {
      name        = "stable-${formatdate("YYYY-MM-DD_hh-mm-ss", time_static.aws-windows.rfc3339)}"
      description = "The stable version of the template."
      directory   = "${path.module}/templates/aws-windows"
      active      = true
    }
  ]
}

##
# AWS EC2 DevContainer
##

data "archive_file" "aws-devcontainer" {
  type        = "zip"
  excludes    = ["${path.module}/templates/aws-devcontainer/.terraform"]
  source_dir  = "${path.module}/templates/aws-devcontainer"
  output_path = "${path.module}/templates/aws-devcontainer.zip"
}

resource "time_static" "aws-devcontainer" {
  triggers = {
    run_on_checksum = "${data.archive_file.aws-devcontainer.id}"
  }
}

resource "coderd_template" "aws-devcontainer" {

  depends_on = [module.coder-ext-prov]

  name            = "aws-devcontainer"
  organization_id = data.coderd_organization.default.id
  display_name    = "AWS EC2 (Linux with Devcontainer)"
  description     = "Provision an AWS EC2 Linux VM running DevContainers."
  icon            = "https://${var.domain_name}/icon/aws.svg"
  versions = [
    {
      name        = "stable-${formatdate("YYYY-MM-DD_hh-mm-ss", time_static.aws-devcontainer.rfc3339)}"
      description = "The stable version of the template."
      directory   = "${path.module}/templates/aws-devcontainer"
      active      = true
    }
  ]
}