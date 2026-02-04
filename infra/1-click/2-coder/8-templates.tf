##
# Coder Template Push
##

data "coderd_organization" "default" {

  # depends_on = [ coderd_license.enterprise ]

  is_default = true
}

data "coderd_group" "everyone" {

  # depends_on = [ coderd_license.enterprise ]

  organization_id = data.coderd_organization.default.id
  name            = "Everyone"
}

data "archive_file" "k8s-default" {
  type        = "zip"
  excludes    = ["${path.module}/templates/kubernetes/.terraform"]
  source_dir  = "${path.module}/templates/kubernetes"
  output_path = "/tmp/kubernetes.zip"
}

resource "time_static" "k8s-default" {
  triggers = {
    run_on_ip_changes = data.aws_eip.coder.private_ip
    run_on_checksum = "${data.archive_file.k8s-default.id}"
  }
}

resource "coderd_template" "k8s-default" {

  # depends_on = [ coderd_license.enterprise ]

  name = "kubernetes"
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
        name = "namespace"
        value = "coder"
        }, {
        name  = "use_kubeconfig"
        value = tostring(false)
      }, {
        name = "host_ip"
        value = data.aws_eip.coder.private_ip
        }]
    }
  ]
  acl = var.coder_license == "" ? null :{
    users = []
    groups = [{
      id   = data.coderd_group.everyone.id
      role = "use"
    }]
  }
}

data "archive_file" "k8s-claude" {

  count = var.coder_license != "" ? 1 : 0

  type        = "zip"
  excludes    = ["${path.module}/templates/kubernetes-claude/.terraform"]
  source_dir  = "${path.module}/templates/kubernetes-claude"
  output_path = "/tmp/kubernetes-claude.zip"
}

resource "time_static" "k8s-claude" {

  count = var.coder_license != "" ? 1 : 0

  triggers = {
    run_on_ip_changes = data.aws_eip.coder.private_ip
    run_on_checksum = "${data.archive_file.k8s-claude[0].id}"
  }
}

##
# NOTICE: This template requires a Premium license as it includes the following:
# - AI Bridge
# - Agent Boundaries
##

resource "coderd_template" "k8s-claude" {

  # depends_on = [ coderd_license.enterprise ]
  count = var.coder_license != "" ? 1 : 0

  name = "kubernetes-claude"
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
        name = "namespace"
        value = "coder"
        }, {
        name  = "use_kubeconfig"
        value = tostring(false)
        }, {
        name = "host_ip"
        value = data.aws_eip.coder.private_ip
        }]
    }
  ]
  acl = {
    users = []
    groups = [{
      id   = data.coderd_group.everyone.id
      role = "use"
    }]
  }
}