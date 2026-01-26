data "coderd_group" "everyone" {
  organization_id = data.coderd_organization.default.id
  name = "Everyone"
}

data "archive_file" "k8s-default" {
  type        = "zip"
  excludes    = ["${path.module}/templates/kubernetes/.terraform"]
  source_dir = "${path.module}/templates/kubernetes"
  output_path = "/tmp/kubernetes.zip"
}

resource "time_static" "k8s-default" {
    triggers = {
        run_on_checksum = "${data.archive_file.k8s-default.id}" 
    }
}

resource "coderd_template" "k8s-default" {
  name        = "kubernetes"
  # organization_id = module.default-ws.coderd_organization_id
  organization_id = data.coderd_organization.default.id
  display_name = "Kubernetes (Deployment)"
  description = "Provision Kubernetes Deployments as Coder workspaces"
  icon =  "https://${var.domain_name}/icon/k8s.png"
  versions = [
    {
      name        = "stable-${formatdate("YYYY-MM-DD_hh-mm-ss", time_static.k8s-default.rfc3339)}"
      description = "The stable version of the template."
      directory   = "${path.module}/templates/kubernetes"
      active = true
      tf_vars = [{
        name  = "namespace"
        # value = kubernetes_namespace.coder-ws.metadata[0].name
        value = "coder"
      },{
        name = "use_kubeconfig"
        value = tostring(false)
    }]
    }
  ]
  acl = {
    users = []
    groups = [{
        id = data.coderd_group.everyone.id
        role = "use"
    }]
  }
}