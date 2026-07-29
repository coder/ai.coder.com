provider "aws" {
  profile = var.profile
  region  = var.region
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

provider "grafana" {
  url                = var.grafana_endpoint
  auth               = var.grafana_token
  retries            = 100
  retry_wait         = 10
  retry_status_codes = toset(["429", "5xx"])
}

data "aws_db_instance" "coder" {
  db_instance_identifier = var.coder_db_rds_id
}

locals {
  namespace = "coder-observability"
  # coderd_selector  = "pod=~`coder.*`, pod!~`.*provisioner.*`, namespace=`${local.coderd_namespace}`"
  # coderd_selector = "pod=~`coder.*`, pod!~`.*provisioner.*`, namespace=~`(coder)`"
  coderd_selector = "pod=~`coder.*`, namespace=~`coder`"

  provisionerd_selector = "pod=~`coder-provisioner.*`, namespace=~`(coder-ws|coder-ws-experiment|coder-ws-demo)`"

  # workspaces_selector     = "namespace=`coder-ws*`"
  workspaces_selector     = "pod!~`coder.*`, namespace=~`(coder-ws|coder-ws-experiment|coder-ws-demo)`"
  non_workspaces_selector = "namespace=~`(coder|coder-ws|coder-ws-experiment|coder-ws-demo)`"

  dashboard_timerange = "12h"
  dashboard_refresh   = "30s"

  dashboards_path = "${path.module}/dashboards"
  dashboards = {
    "coder-dashboard-status" = {
      local_path = "${local.dashboards_path}/status.json"
      args = {
        HELM_NAMESPACE        = local.namespace
        CODERD_SELECTOR       = local.coderd_selector
        PROVISIONERD_SELECTOR = local.provisionerd_selector
        WORKSPACES_SELECTOR   = local.workspaces_selector
        PROMETHEUS_JOB        = "${local.namespace}/prometheus/server"
        LOKI_JOB              = "${local.namespace}/loki"
        GRAFANA_AGENT_JOB     = "${local.namespace}/grafana-agent/grafana-agent"
      }
    },
    "coder-dashboard-coderd" = {
      local_path = "${local.dashboards_path}/coderd.json"
      args = {
        DASHBOARD_TIMERANGE = local.dashboard_timerange
        DASHBOARD_REFRESH   = local.dashboard_refresh
        CODERD_SELECTOR     = local.coderd_selector
      }
    },
    "coder-dashboard-provisionerd" = {
      local_path = "${local.dashboards_path}/provisionerd.json"
      args = {
        DASHBOARD_TIMERANGE     = local.dashboard_timerange
        DASHBOARD_REFRESH       = local.dashboard_refresh
        PROVISIONERD_SELECTOR   = local.provisionerd_selector
        NON_WORKSPACES_SELECTOR = local.non_workspaces_selector
      }
    },
    "coder-dashboard-workspaces" = {
      local_path = "${local.dashboards_path}/workspaces.json"
      args = {
        DASHBOARD_TIMERANGE     = local.dashboard_timerange
        DASHBOARD_REFRESH       = local.dashboard_refresh
        WORKSPACES_SELECTOR     = local.workspaces_selector
        NON_WORKSPACES_SELECTOR = local.non_workspaces_selector
      }
    },
    "coder-dashboard-workspace-detail" = {
      local_path = "${local.dashboards_path}/workspace_detail.json"
      args = {
        DASHBOARD_TIMERANGE     = local.dashboard_timerange
        DASHBOARD_REFRESH       = local.dashboard_refresh
        WORKSPACES_SELECTOR     = local.workspaces_selector
        NON_WORKSPACES_SELECTOR = local.non_workspaces_selector
      }
    },
    "coder-dashboard-prebuilds" = {
      local_path = "${local.dashboards_path}/prebuilds.json"
      args = {
        DASHBOARD_TIMERANGE = local.dashboard_timerange
        DASHBOARD_REFRESH   = local.dashboard_refresh
      }
    },
    "coder-dashboard-aibridge" = {
      local_path = "${local.dashboards_path}/aibridge.json"
      args       = {}
    },
    "coder-dashboard-boundary" = {
      local_path = "${local.dashboards_path}/boundary.json"
      args = {
        DASHBOARD_TIMERANGE    = local.dashboard_timerange
        DASHBOARD_REFRESH      = local.dashboard_refresh
        NON_WORKSPACE_SELECTOR = local.non_workspaces_selector
      }
    }
    # {
    #   name = "coder-dashboard-proxyd"
    #   local_path = "${local.dashboards_path}/proxyd.json"
    #   args = {
    #     DASHBOARD_TIMERANGE = local.dashboard_timerange
    #     DASHBOARD_REFRESH   = local.dashboard_refresh
    #     CODERD_SELECTOR     = local.coderd_selector
    #   }
    # }
  }
}

resource "grafana_data_source" "cloudwatch" {
  type        = "cloudwatch"
  name        = "cloudwatch"
  access_mode = "proxy"

  json_data_encoded = jsonencode({
    defaultRegion = var.region
    authType      = "default"
  })
}

resource "grafana_data_source" "prometheus" {
  type        = "prometheus"
  name        = "prometheus"
  url         = var.prometheus_endpoint
  access_mode = "proxy"
  is_default  = true

  basic_auth_enabled = false
  json_data_encoded = jsonencode({
    sigV4AuthType = "default"
    httpMethod    = "POST"
    sigV4Auth     = true
    sigV4Region   = var.region
  })
}

data "kubernetes_service_v1" "loki-gateway" {

  metadata {
    name      = "coder-observability-loki"
    namespace = local.namespace
  }
}

resource "grafana_data_source" "loki-gateway" {
  type        = "loki"
  name        = "loki"
  access_mode = "proxy"
  url         = "http://${data.kubernetes_service_v1.loki-gateway.status[0].load_balancer[0].ingress[0].hostname}:3100"
}

data "aws_secretsmanager_secret" "grafana" {
  name = "rds-${var.grafana_db_user}"
}

data "aws_secretsmanager_secret_version" "grafana" {
  secret_id     = data.aws_secretsmanager_secret.grafana.id
  version_stage = "AWSCURRENT"
}

resource "grafana_data_source" "postgres" {
  type        = "grafana-postgresql-datasource"
  name        = "postgres"
  url         = data.aws_db_instance.coder.endpoint
  access_mode = "proxy"
  is_default  = false

  username = var.grafana_db_user

  json_data_encoded = jsonencode({
    database        = data.aws_db_instance.coder.db_name
    sslmode         = "require"
    postgresVersion = "903" # Set your specific version: https://registry.terraform.io/providers/grafana/grafana/1.28.2/docs/resources/data_source#postgres_version-1
    timescaledb     = false # Toggle true if using TimescaleDB
  })

  secure_json_data_encoded = sensitive(data.aws_secretsmanager_secret_version.grafana.secret_string)
}

resource "grafana_dashboard" "this" {
  for_each    = local.dashboards
  config_json = templatefile(each.value.local_path, each.value.args)
}

resource "grafana_organization_preferences" "this" {
  home_dashboard_uid = grafana_dashboard.this["coder-dashboard-status"].uid
  theme              = "system"
  timezone           = "browser"
  week_start         = "monday"
}
