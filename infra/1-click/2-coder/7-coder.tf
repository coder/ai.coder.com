variable "domain_name" {
  type = string
}

variable "coder_admin_email" {
  type = string
  default = "admin@coder.com"
}

variable "coder_admin_password" {
  type = string
  sensitive = true
  default = "Th1s1sN0TS3CuR3!!"
}

##
# Coder MUST be in a reachable state by now
##

data "external" "fetch-token" {

  program = ["bash", "${path.module}/fetch.sh"]

  query = {
    coder_url = "https://${var.domain_name}"
    admin_email = var.coder_admin_email
    admin_password = var.coder_admin_password
  }

}

provider "coderd" {
  url = "https://${var.domain_name}"
  token = data.external.fetch-token.result.session_token
}

output "coder_session_token" {
  value = data.external.fetch-token.result.session_token
}

locals {
  image_repo = "ghcr.io/coder/coder"
  image_tag = "v2.29.1"
  service_account_labels = {
    "app.kubernetes.io/instance" = "coder-provisioner"
    "app.kubernetes.io/name"     = "coder-provisioner"
    "app.kubernetes.io/part-of"  = "coder-provisioner"
  }
  node_selector = {
    "node.coder.io/managed-by" = "karpenter"
    "node.coder.io/used-for"   = "coder-provisioner"
  }
  tolerations = [{
    key      = "dedicated"
    operator = "Equal"
    value    = "coder-provisioner"
    effect   = "NoSchedule"
  }]
}

module "default-ws" {

  depends_on = [ data.external.fetch-token ]

  source                    = "../../../modules/k8s/bootstrap/coder-provisioner"

  cluster_name              = var.name
  cluster_oidc_provider_arn = data.aws_iam_openid_connect_provider.coder.arn

  coder_organization_name = "coder"

  namespace                        = "coder-ws"
  image_repo                       = local.image_repo
  image_tag                        = local.image_tag
  ws_service_account_name          = "coder-ws"
  ws_service_account_labels        = {
    "app.kubernetes.io/instance" = "coder-provisioner"
    "app.kubernetes.io/name"     = "coder-provisioner"
    "app.kubernetes.io/part-of"  = "coder-provisioner"
  }
  provisioner_service_account_name = "coder"
  replica_count                    = 2
  primary_access_url               = "https://${var.domain_name}"
  env_vars = {
    CODER_PROMETHEUS_ENABLE              = "true"
    CODER_PROMETHEUS_COLLECT_AGENT_STATS = "true"
    CODER_PROMETHEUS_COLLECT_DB_METRICS  = "true"
  }
  node_selector = local.node_selector
  tolerations   = local.tolerations
}