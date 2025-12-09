terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 3.1.1"
    }
    kubernetes = {
      source = "hashicorp/kubernetes"
    }
    coderd = {
      source = "coder/coderd"
    }
    acme = {
      source = "vancluever/acme"
    }
    tls = {
      source = "hashicorp/tls"
    }
  }
  backend "s3" {}
}

##
# Cluster Authentication Inputs
##

variable "cluster_name" {
  type = string
}

variable "cluster_region" {
  type = string
}

variable "cluster_profile" {
  type    = string
  default = "default"
}

variable "cluster_oidc_provider_arn" {
  type = string
}

variable "addon_namespace" {
  type    = string
  default = "observability"
}

variable "helm_coder_observability_timeout" {
  type    = number
  default = 120 # In Seconds
}

variable "helm_coder_observability_version" {
  type    = string
  default = "0.6.1"
}

variable "helm_prometheus_operator_version" {
  type    = string
  default = "24.0.2"
}

variable "helm_prometheus_operator_timeout" {
  type    = number
  default = 120 # In Seconds
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

provider "helm" {
  kubernetes = {
    host                   = data.aws_eks_cluster.this.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)
    token                  = data.aws_eks_cluster_auth.this.token
  }
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.this.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.this.token
}

##
# Coder DB Inputs
##

variable "coder_db_username" {
  type      = string
  sensitive = true
}

variable "coder_db_password" {
  description = "Coder's DB password"
  type        = string
  sensitive   = true
}

variable "coder_db_host" {
  type      = string
  sensitive = true
}

variable "coder_db_port" {
  type    = number
  default = 5432
}

##
# Coder Scraping Configs
##

variable "coderd_selector" {
  type    = string
  default = "pod=~`coder.*`, pod!~`.*provisioner.*`"
}

variable "provisionerd_selector" {
  type    = string
  default = "pod=~`coder-provisioner.*"
}

variable "coder_workspaces_selector" {
  type    = string
  default = "namespace=`coder-workspaces`"
}

variable "coderd_namespace" {
  type    = string
  default = "coder"
}

##
# Loki Inputs
##

variable "loki_iam_role_name" {
  type    = string
  default = "loki-s3-access"
}

variable "loki_s3_chunk_bucket_name" {
  type      = string
  sensitive = true
}

variable "loki_s3_ruler_bucket_name" {
  type      = string
  sensitive = true
}

variable "loki_s3_bucket_region" {
  type = string
}

variable "loki_replicas" {
  type    = number
  default = 3

  validation {
    condition     = var.loki_replicas >= 0
    error_message = "'loki_replicas' must be >= 0."
  }
}

##
# Grafana Inputs
##

variable "grafana_security_key" {
  description = "Security Key used for signing data source settings e.g. secrets + passwords"
  type        = string
  sensitive   = true
}

variable "grafana_auth_username" {
  description = "Grafana Endpoint username"
  type        = string
  sensitive   = true
}

variable "grafana_auth_password" {
  description = "Grafana Endpoint password"
  type        = string
  sensitive   = true
}

variable "grafana_db_name" {
  description = "Grafana DB name"
  type        = string
  default     = "grafana"
}

variable "grafana_db_user" {
  description = "Grafana DB username"
  type        = string
  default     = "grafana"
}

variable "grafana_db_password" {
  description = "Grafana DB password"
  type        = string
  sensitive   = true
}

variable "grafana_db_host" {
  description = "Grafana DB hostname"
  type        = string
  sensitive   = true
}

variable "grafana_admin_username" {
  description = "Grafana Admin username"
  type        = string
  sensitive   = true
}

variable "grafana_admin_password" {
  description = "Grafana Admin password"
  type        = string
  sensitive   = true
}

variable "grafana_root_domain" {
  type = string
}

variable "grafana_subdomain" {
  type = string
}

variable "grafana_cert_name" {
  type    = string
  default = "grafana-certs"
}

variable "grafana_cert_mnt_path" {
  type    = string
  default = "/etc/ssl/certs"
}

locals {
  dashboards-path = "${path.module}/dashboards"
  # coderd_selector  = "pod=~`coder.*`, pod!~`.*provisioner.*`, namespace=`${local.coderd_namespace}`"
  coderd_selector = "pod=~`coder.*`, pod!~`.*provisioner.*`, namespace=~`(coder)`"

  provisionerd_selector = "pod=~`coder-provisioner.*`, namespace=~`(coder-ws|coder-ws-experiment|coder-ws-demo)`"

  # workspaces_selector     = "namespace=`coder-ws*`"
  workspaces_selector     = "pod!~`coder.*`, namespace=~`(coder-ws|coder-ws-experiment|coder-ws-demo)`"
  non_workspaces_selector = "namespace=~`(coder|coder-ws|coder-ws-experiment|coder-ws-demo)`"

  dashboard_timerange = "12h"
  dashboard_refresh   = "30s"
}

module "monitoring" {
  source = "../../../../../modules/k8s/bootstrap/monitoring"

  namespace                        = var.addon_namespace
  helm_coder_observability_version = var.helm_coder_observability_version
  helm_coder_observability_timeout = var.helm_coder_observability_timeout
  helm_prometheus_operator_version = var.helm_prometheus_operator_version
  helm_prometheus_operator_timeout = var.helm_prometheus_operator_timeout
  cluster_name                     = var.cluster_name
  cluster_oidc_provider_arn        = var.cluster_oidc_provider_arn

  coder_db_username = var.coder_db_username
  coder_db_password = var.coder_db_password
  coder_db_host     = var.coder_db_host
  coder_db_port     = var.coder_db_port

  loki_s3_chunk_bucket_name = var.loki_s3_chunk_bucket_name
  loki_s3_ruler_bucket_name = var.loki_s3_ruler_bucket_name
  loki_s3_bucket_region     = var.loki_s3_bucket_region
  loki_iam_role_name        = var.loki_iam_role_name
  loki_replicas             = var.loki_replicas

  grafana_security_key   = var.grafana_security_key
  grafana_auth_username  = var.grafana_auth_username
  grafana_auth_password  = var.grafana_auth_password
  grafana_db_user        = var.grafana_db_user
  grafana_db_name        = var.grafana_db_name
  grafana_db_password    = var.grafana_db_password
  grafana_db_host        = var.grafana_db_host
  grafana_admin_username = var.grafana_admin_username
  grafana_admin_password = var.grafana_admin_password
  grafana_root_domain    = var.grafana_root_domain
  grafana_subdomain      = var.grafana_subdomain
  grafana_cert_name      = var.grafana_cert_name
  grafana_cert_mnt_path  = var.grafana_cert_mnt_path
  grafana_replicas       = 2
  grafana_service_annotations = {
    "service.beta.kubernetes.io/aws-load-balancer-nlb-target-type" = "instance"
    "service.beta.kubernetes.io/aws-load-balancer-scheme"          = "internet-facing"
    "service.beta.kubernetes.io/aws-load-balancer-attributes"      = "deletion_protection.enabled=true"
  }

  dashboards = [
    {
      name      = "coder-dashboard-status"
      localPath = "${local.dashboards-path}/status.json"
      args = {
        HELM_NAMESPACE        = var.addon_namespace
        CODERD_SELECTOR       = local.coderd_selector
        PROVISIONERD_SELECTOR = local.provisionerd_selector
        WORKSPACES_SELECTOR   = local.workspaces_selector
        PROMETHEUS_JOB        = "${var.addon_namespace}/prometheus/server"
        LOKI_JOB              = "${var.addon_namespace}/loki"
        GRAFANA_AGENT_JOB     = "${var.addon_namespace}/grafana-agent/grafana-agent"
      }
    },
    {
      name      = "coder-dashboard-coderd"
      localPath = "${local.dashboards-path}/coderd.json"
      args = {
        DASHBOARD_TIMERANGE = local.dashboard_timerange
        DASHBOARD_REFRESH   = local.dashboard_refresh
        CODERD_SELECTOR     = local.coderd_selector
      }
    },
    {
      name      = "coder-dashboard-provisionerd"
      localPath = "${local.dashboards-path}/provisionerd.json"
      args = {
        DASHBOARD_TIMERANGE     = local.dashboard_timerange
        DASHBOARD_REFRESH       = local.dashboard_refresh
        PROVISIONERD_SELECTOR   = local.provisionerd_selector
        NON_WORKSPACES_SELECTOR = local.non_workspaces_selector
      }
    },
    {
      name      = "coder-dashboard-workspaces"
      localPath = "${local.dashboards-path}/workspaces.json"
      args = {
        DASHBOARD_TIMERANGE     = local.dashboard_timerange
        DASHBOARD_REFRESH       = local.dashboard_refresh
        WORKSPACES_SELECTOR     = local.workspaces_selector
        NON_WORKSPACES_SELECTOR = local.non_workspaces_selector
      }
    },
    {
      name      = "coder-dashboard-workspace-detail"
      localPath = "${local.dashboards-path}/workspace_detail.json"
      args = {
        DASHBOARD_TIMERANGE     = local.dashboard_timerange
        DASHBOARD_REFRESH       = local.dashboard_refresh
        WORKSPACES_SELECTOR     = local.workspaces_selector
        NON_WORKSPACES_SELECTOR = local.non_workspaces_selector
      }
    },
    {
      name      = "coder-dashboard-prebuilds"
      localPath = "${local.dashboards-path}/prebuilds.json"
      args = {
        DASHBOARD_TIMERANGE = local.dashboard_timerange
        DASHBOARD_REFRESH   = local.dashboard_refresh
      }
    },
    {
      name      = "coder-dashboard-aibridge"
      localPath = "${local.dashboards-path}/aibridge.json"
      args      = {}
    },
    # {
    #   name = "coder-dashboard-proxyd"
    #   localPath = "${local.dashboards-path}/proxyd.json"
    #   args = {
    #     DASHBOARD_TIMERANGE = local.dashboard_timerange
    #     DASHBOARD_REFRESH   = local.dashboard_refresh
    #     CODERD_SELECTOR     = local.coderd_selector
    #   }
    # }
  ]

  # service_annotations = {
  #   "service.beta.kubernetes.io/aws-load-balancer-nlb-target-type" = "instance"
  #   "service.beta.kubernetes.io/aws-load-balancer-scheme"          = "internet-facing"
  #   "service.beta.kubernetes.io/aws-load-balancer-attributes"      = "deletion_protection.enabled=true"
  # }
  # node_selector = {
  #   "node.coder.io/managed-by" = "karpenter"
  #   "node.coder.io/used-for"   = "coder"
  # }
  # tolerations = [{
  #   key      = "dedicated"
  #   operator = "Equal"
  #   value    = "coder"
  #   effect   = "NoSchedule"
  # }]
  # topology_spread_constraints = [{
  #   max_skew           = 1
  #   topology_key       = "kubernetes.io/hostname"
  #   when_unsatisfiable = "ScheduleAnyway"
  #   label_selector = {
  #     match_labels = {
  #       "app.kubernetes.io/name"    = "coder"
  #       "app.kubernetes.io/part-of" = "coder"
  #     }
  #   }
  #   match_label_keys = [
  #     "app.kubernetes.io/instance"
  #   ]
  # }]
  # pod_anti_affinity_preferred_during_scheduling_ignored_during_execution = [{
  #   weight = 100
  #   pod_affinity_term = {
  #     label_selector = {
  #       match_labels = {
  #         "app.kubernetes.io/instance" = "coder-v2"
  #         "app.kubernetes.io/name"     = "coder"
  #         "app.kubernetes.io/part-of"  = "coder"
  #       }
  #     }
  #     topology_key = "kubernetes.io/hostname"
  #   }
  # }]
}