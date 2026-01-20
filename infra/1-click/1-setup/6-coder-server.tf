##
# Coder Helm Chart Installation w/ auxillary dependcies on:
# - cert-manager
# - karpenter
# - external-dns
# - external-secrets
##

variable "domain_name" {
  type = string
}

variable "coder_username" {
  description = "Coder DB's username."
  type        = string
  default     = "coder"
}

variable "coder_password" {
  description = "Coder DB's password."
  type        = string
  sensitive   = true
  default     = "th1s1sn0tas3cur3pass0wrd"
}

variable "coder_license" {
  type = string
  sensitive = true
  default = ""
}

variable "coder_admin_email" {
  type = string
  default = "admin@coder.com"
}

variable "coder_admin_username" {
  type = string
  default = "admin"
}

variable "coder_admin_password" {
  type = string
  sensitive = true
  default = "Th1s1sN0TS3CuR3!!"
}

module "coder-server" {

  depends_on = [ kubernetes_manifest.nodepool ]

  source = "../../../modules/k8s/bootstrap/coder-server"

  cluster_name              = var.name
  cluster_oidc_provider_arn = data.aws_iam_openid_connect_provider.coder.arn

  namespace                       = "coder"
  
  replica_count                   = 2
  helm_version                    = "2.29.1"
  image_repo                      = "ghcr.io/coder/coder"
  image_tag                       = "v2.29.1"
  primary_access_url              = "https://${var.domain_name}"
  wildcard_access_url             = "*.${var.domain_name}"
  db_secret_url                   = "postgresql://${var.coder_username}:${var.coder_password}@${data.aws_db_instance.coder.endpoint}/coder"
  
  coder_builtin_provisioner_count = 0
  # coder_github_allowed_orgs       = var.coder_github_allowed_orgs

  ssl_cert_config = {
    name          = var.domain_name
    caissuer = kubernetes_manifest.default-issuer.manifest.metadata.name
    secretissuer = kubernetes_manifest.secret-store.manifest.metadata.name
    create_secret = true
  }

  enable_oidc = false
  enable_oauth = false
  enable_github_external_auth = false

  tags                                      = {}

  service_annotations = {
    "service.beta.kubernetes.io/aws-load-balancer-nlb-target-type" = "instance"
    "service.beta.kubernetes.io/aws-load-balancer-scheme"          = "internet-facing"
    "service.beta.kubernetes.io/aws-load-balancer-attributes"      = "deletion_protection.enabled=false"
    "external-dns.alpha.kubernetes.io/hostname"                    = "${var.domain_name}"
    "external-dns.alpha.kubernetes.io/ttl"                         = 30
  }

  node_selector = kubernetes_manifest.nodepool["coder-server"].manifest.spec.template.metadata.labels
  tolerations = [ for toleration in kubernetes_manifest.nodepool["coder-server"].manifest.spec.template.spec.taints : {
      key      = toleration.key
      operator = "Equal"
      value    = toleration.value
      effect   = toleration.effect
  }]

  topology_spread_constraints = [{
    max_skew           = 1
    topology_key       = "kubernetes.io/hostname"
    when_unsatisfiable = "ScheduleAnyway"
    label_selector = {
      match_labels = {
        "app.kubernetes.io/name"    = "coder"
        "app.kubernetes.io/part-of" = "coder"
      }
    }
    match_label_keys = [
      "app.kubernetes.io/instance"
    ]
  }]
  pod_anti_affinity_preferred_during_scheduling_ignored_during_execution = [{
    weight = 100
    pod_affinity_term = {
      label_selector = {
        match_labels = {
          "app.kubernetes.io/instance" = "coder-v2"
          "app.kubernetes.io/name"     = "coder"
          "app.kubernetes.io/part-of"  = "coder"
        }
      }
      topology_key = "kubernetes.io/hostname"
    }
  }]
}

# Wait for DNS propagation. May require multiple redeploys
resource "time_sleep" "wait_for_dns" {
  create_duration = "300s"
  depends_on = [ module.coder-server ]
}

data "external" "first-user" {
  
  depends_on = [ time_sleep.wait_for_dns ]

  program = ["bash", "${path.module}/scripts/first-user.sh"]

  query = {
    access_url = "https://${var.domain_name}"
    admin_email = var.coder_admin_email
    admin_username = var.coder_admin_username
    admin_password = var.coder_admin_password
  }

}

output "coder_session_token" {
  value = data.external.first-user.result.session_token
}

data "external" "add-license" {
  
  count = var.coder_license != "" ? 1 : 0

  depends_on = [ time_sleep.wait_for_dns ]

  program = ["bash", "${path.module}/scripts/add-license.sh"]

  query = {
    access_url = "https://${var.domain_name}"
    license_key = var.coder_license
    session_token = data.external.first-user.result.session_token
  }

}

# locals {
#   dashboards-path = "${path.module}/dashboards"
#   # coderd_selector  = "pod=~`coder.*`, pod!~`.*provisioner.*`, namespace=`${local.coderd_namespace}`"
#   coderd_selector = "pod=~`coder.*`, pod!~`.*provisioner.*`, namespace=~`(coder)`"

#   provisionerd_selector = "pod=~`coder-provisioner.*`, namespace=~`(coder-ws|coder-ws-experiment|coder-ws-demo)`"

#   # workspaces_selector     = "namespace=`coder-ws*`"
#   workspaces_selector     = "pod!~`coder.*`, namespace=~`(coder-ws|coder-ws-experiment|coder-ws-demo)`"
#   non_workspaces_selector = "namespace=~`(coder|coder-ws|coder-ws-experiment|coder-ws-demo)`"

#   dashboard_timerange = "12h"
#   dashboard_refresh   = "30s"
# }

# module "monitoring" {
#   source = "../../../modules/k8s/bootstrap/monitoring"

#   namespace                        = var.addon_namespace
#   helm_coder_observability_version = var.helm_coder_observability_version
#   helm_coder_observability_timeout = var.helm_coder_observability_timeout
#   helm_prometheus_operator_version = var.helm_prometheus_operator_version
#   helm_prometheus_operator_timeout = var.helm_prometheus_operator_timeout
#   cluster_name                     = var.cluster_name
#   cluster_oidc_provider_arn        = var.cluster_oidc_provider_arn

#   coder_db_username = var.coder_db_username
#   coder_db_password = var.coder_db_password
#   coder_db_host     = var.coder_db_host
#   coder_db_port     = var.coder_db_port

#   loki_s3_chunk_bucket_name = var.loki_s3_chunk_bucket_name
#   loki_s3_ruler_bucket_name = var.loki_s3_ruler_bucket_name
#   loki_s3_bucket_region     = var.loki_s3_bucket_region
#   loki_iam_role_name        = var.loki_iam_role_name
#   loki_replicas             = var.loki_replicas

#   grafana_security_key   = var.grafana_security_key
#   grafana_auth_username  = var.grafana_auth_username
#   grafana_auth_password  = var.grafana_auth_password
#   grafana_db_user        = var.grafana_db_user
#   grafana_db_name        = var.grafana_db_name
#   grafana_db_password    = var.grafana_db_password
#   grafana_db_host        = var.grafana_db_host
#   grafana_admin_username = var.grafana_admin_username
#   grafana_admin_password = var.grafana_admin_password
#   grafana_root_domain    = var.grafana_root_domain
#   grafana_subdomain      = var.grafana_subdomain
#   grafana_cert_name      = var.grafana_cert_name
#   grafana_cert_mnt_path  = var.grafana_cert_mnt_path
#   grafana_replicas       = 2
#   grafana_service_annotations = {
#     "service.beta.kubernetes.io/aws-load-balancer-nlb-target-type" = "instance"
#     "service.beta.kubernetes.io/aws-load-balancer-scheme"          = "internet-facing"
#     "service.beta.kubernetes.io/aws-load-balancer-attributes"      = "deletion_protection.enabled=true"
#   }

#   dashboards = [
#     {
#       name      = "coder-dashboard-status"
#       localPath = "${local.dashboards-path}/status.json"
#       args = {
#         HELM_NAMESPACE        = var.addon_namespace
#         CODERD_SELECTOR       = local.coderd_selector
#         PROVISIONERD_SELECTOR = local.provisionerd_selector
#         WORKSPACES_SELECTOR   = local.workspaces_selector
#         PROMETHEUS_JOB        = "${var.addon_namespace}/prometheus/server"
#         LOKI_JOB              = "${var.addon_namespace}/loki"
#         GRAFANA_AGENT_JOB     = "${var.addon_namespace}/grafana-agent/grafana-agent"
#       }
#     },
#     {
#       name      = "coder-dashboard-coderd"
#       localPath = "${local.dashboards-path}/coderd.json"
#       args = {
#         DASHBOARD_TIMERANGE = local.dashboard_timerange
#         DASHBOARD_REFRESH   = local.dashboard_refresh
#         CODERD_SELECTOR     = local.coderd_selector
#       }
#     },
#     {
#       name      = "coder-dashboard-provisionerd"
#       localPath = "${local.dashboards-path}/provisionerd.json"
#       args = {
#         DASHBOARD_TIMERANGE     = local.dashboard_timerange
#         DASHBOARD_REFRESH       = local.dashboard_refresh
#         PROVISIONERD_SELECTOR   = local.provisionerd_selector
#         NON_WORKSPACES_SELECTOR = local.non_workspaces_selector
#       }
#     },
#     {
#       name      = "coder-dashboard-workspaces"
#       localPath = "${local.dashboards-path}/workspaces.json"
#       args = {
#         DASHBOARD_TIMERANGE     = local.dashboard_timerange
#         DASHBOARD_REFRESH       = local.dashboard_refresh
#         WORKSPACES_SELECTOR     = local.workspaces_selector
#         NON_WORKSPACES_SELECTOR = local.non_workspaces_selector
#       }
#     },
#     {
#       name      = "coder-dashboard-workspace-detail"
#       localPath = "${local.dashboards-path}/workspace_detail.json"
#       args = {
#         DASHBOARD_TIMERANGE     = local.dashboard_timerange
#         DASHBOARD_REFRESH       = local.dashboard_refresh
#         WORKSPACES_SELECTOR     = local.workspaces_selector
#         NON_WORKSPACES_SELECTOR = local.non_workspaces_selector
#       }
#     },
#     {
#       name      = "coder-dashboard-prebuilds"
#       localPath = "${local.dashboards-path}/prebuilds.json"
#       args = {
#         DASHBOARD_TIMERANGE = local.dashboard_timerange
#         DASHBOARD_REFRESH   = local.dashboard_refresh
#       }
#     },
#     {
#       name      = "coder-dashboard-aibridge"
#       localPath = "${local.dashboards-path}/aibridge.json"
#       args      = {}
#     },
#     # {
#     #   name = "coder-dashboard-proxyd"
#     #   localPath = "${local.dashboards-path}/proxyd.json"
#     #   args = {
#     #     DASHBOARD_TIMERANGE = local.dashboard_timerange
#     #     DASHBOARD_REFRESH   = local.dashboard_refresh
#     #     CODERD_SELECTOR     = local.coderd_selector
#     #   }
#     # }
#   ]

#   # service_annotations = {
#   #   "service.beta.kubernetes.io/aws-load-balancer-nlb-target-type" = "instance"
#   #   "service.beta.kubernetes.io/aws-load-balancer-scheme"          = "internet-facing"
#   #   "service.beta.kubernetes.io/aws-load-balancer-attributes"      = "deletion_protection.enabled=true"
#   # }
#   # node_selector = {
#   #   "node.coder.io/managed-by" = "karpenter"
#   #   "node.coder.io/used-for"   = "coder"
#   # }
#   # tolerations = [{
#   #   key      = "dedicated"
#   #   operator = "Equal"
#   #   value    = "coder"
#   #   effect   = "NoSchedule"
#   # }]
#   # topology_spread_constraints = [{
#   #   max_skew           = 1
#   #   topology_key       = "kubernetes.io/hostname"
#   #   when_unsatisfiable = "ScheduleAnyway"
#   #   label_selector = {
#   #     match_labels = {
#   #       "app.kubernetes.io/name"    = "coder"
#   #       "app.kubernetes.io/part-of" = "coder"
#   #     }
#   #   }
#   #   match_label_keys = [
#   #     "app.kubernetes.io/instance"
#   #   ]
#   # }]
#   # pod_anti_affinity_preferred_during_scheduling_ignored_during_execution = [{
#   #   weight = 100
#   #   pod_affinity_term = {
#   #     label_selector = {
#   #       match_labels = {
#   #         "app.kubernetes.io/instance" = "coder-v2"
#   #         "app.kubernetes.io/name"     = "coder"
#   #         "app.kubernetes.io/part-of"  = "coder"
#   #       }
#   #     }
#   #     topology_key = "kubernetes.io/hostname"
#   #   }
#   # }]
# }