provider "aws" {
  region  = var.region
  profile = var.profile
}

data "aws_eks_cluster" "this" {
  name = var.cluster_name
}

data "aws_eks_cluster_auth" "this" {
  name = var.cluster_name
}

data "aws_iam_openid_connect_provider" "this" {
  url = data.aws_eks_cluster.this.identity[0].oidc[0].issuer
}

data "aws_db_instance" "coder" {
  db_instance_identifier = var.coder_db_rds_id
}

data "aws_db_instance" "grafana" {
  db_instance_identifier = var.grafana_db_rds_id
}

data "aws_s3_bucket" "loki" {
  bucket = var.loki_s3_bucket_name
}

data "aws_region" "this" {}

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

locals {
  dashboards-path = "${path.module}/dashboards"
  # coderd_selector  = "pod=~`coder.*`, pod!~`.*provisioner.*`, namespace=`${local.coderd_namespace}`"
  # coderd_selector = "pod=~`coder.*`, pod!~`.*provisioner.*`, namespace=~`(coder)`"
  coderd_selector = "pod=~`coder.*`, namespace=~`coder`"

  provisionerd_selector = "pod=~`coder-provisioner.*`, namespace=~`(coder-ws|coder-ws-experiment|coder-ws-demo)`"

  # workspaces_selector     = "namespace=`coder-ws*`"
  workspaces_selector     = "pod!~`coder.*`, namespace=~`(coder-ws|coder-ws-experiment|coder-ws-demo)`"
  non_workspaces_selector = "namespace=~`(coder|coder-ws|coder-ws-experiment|coder-ws-demo)`"

  dashboard_timerange = "12h"
  dashboard_refresh   = "30s"
}

locals {
  common_name           = replace(replace(var.domain_name, "https://", ""), "http://", "")
  ssl_vol_friendly_name = replace(local.common_name, ".", "-")
}

resource "kubernetes_manifest" "cert" {

  field_manager {
    force_conflicts = true
  }
  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind       = "Certificate"
    metadata = {
      labels    = {} # var.cert_labels
      name      = local.ssl_vol_friendly_name
      namespace = module.monitoring.namespace
    }
    spec = {
      secretName  = local.ssl_vol_friendly_name
      commonName  = local.common_name
      dnsNames    = [local.common_name]
      duration    = "${90 * 24}h"
      renewBefore = "8h"
      additionalOutputFormats = [{
        type = "CombinedPEM"
        }, {
        type = "DER"
      }]
      issuerRef = {
        kind = "ClusterIssuer"
        name = "issuer"
      }
    }
  }
}

locals {
  azs      = slice(var.azs, 0, 1)
  pub_subs = [for az in local.azs : "${var.vpc_name}-public-${data.aws_region.this.region}${az}"]
  dashboard_config_maps = {
    "coder-dashboard-status" = {
      local_path = "${local.dashboards-path}/status.json"
      mount_path = "/var/lib/grafana/dashboards/coder/0"
      args = {
        HELM_NAMESPACE        = var.namespace
        CODERD_SELECTOR       = local.coderd_selector
        PROVISIONERD_SELECTOR = local.provisionerd_selector
        WORKSPACES_SELECTOR   = local.workspaces_selector
        PROMETHEUS_JOB        = "${var.namespace}/prometheus/server"
        LOKI_JOB              = "${var.namespace}/loki"
        GRAFANA_AGENT_JOB     = "${var.namespace}/grafana-agent/grafana-agent"
      }
    },
    "coder-dashboard-coderd" = {
      local_path = "${local.dashboards-path}/coderd.json"
      mount_path = "/var/lib/grafana/dashboards/coder/1"
      args = {
        DASHBOARD_TIMERANGE = local.dashboard_timerange
        DASHBOARD_REFRESH   = local.dashboard_refresh
        CODERD_SELECTOR     = local.coderd_selector
      }
    },
    "coder-dashboard-provisionerd" = {
      local_path = "${local.dashboards-path}/provisionerd.json"
      mount_path = "/var/lib/grafana/dashboards/coder/2"
      args = {
        DASHBOARD_TIMERANGE     = local.dashboard_timerange
        DASHBOARD_REFRESH       = local.dashboard_refresh
        PROVISIONERD_SELECTOR   = local.provisionerd_selector
        NON_WORKSPACES_SELECTOR = local.non_workspaces_selector
      }
    },
    "coder-dashboard-workspaces" = {
      local_path = "${local.dashboards-path}/workspaces.json"
      mount_path = "/var/lib/grafana/dashboards/coder/3"
      args = {
        DASHBOARD_TIMERANGE     = local.dashboard_timerange
        DASHBOARD_REFRESH       = local.dashboard_refresh
        WORKSPACES_SELECTOR     = local.workspaces_selector
        NON_WORKSPACES_SELECTOR = local.non_workspaces_selector
      }
    },
    "coder-dashboard-workspace-detail" = {
      local_path = "${local.dashboards-path}/workspace_detail.json"
      mount_path = "/var/lib/grafana/dashboards/coder/4"
      args = {
        DASHBOARD_TIMERANGE     = local.dashboard_timerange
        DASHBOARD_REFRESH       = local.dashboard_refresh
        WORKSPACES_SELECTOR     = local.workspaces_selector
        NON_WORKSPACES_SELECTOR = local.non_workspaces_selector
      }
    },
    "coder-dashboard-prebuilds" = {
      local_path = "${local.dashboards-path}/prebuilds.json"
      mount_path = "/var/lib/grafana/dashboards/coder/5"
      args = {
        DASHBOARD_TIMERANGE = local.dashboard_timerange
        DASHBOARD_REFRESH   = local.dashboard_refresh
      }
    },
    "coder-dashboard-aibridge" = {
      local_path = "${local.dashboards-path}/aibridge.json"
      mount_path = "/var/lib/grafana/dashboards/coder/6"
      args       = {}
    },
    "coder-dashboard-boundary" = {
      local_path = "${local.dashboards-path}/boundary.json"
      mount_path = "/var/lib/grafana/dashboards/coder/7"
      args = {
        DASHBOARD_TIMERANGE    = local.dashboard_timerange
        DASHBOARD_REFRESH      = local.dashboard_refresh
        NON_WORKSPACE_SELECTOR = local.non_workspaces_selector
      }
    }
    # {
    #   name = "coder-dashboard-proxyd"
    #   local_path = "${local.dashboards-path}/proxyd.json"
    #   args = {
    #     DASHBOARD_TIMERANGE = local.dashboard_timerange
    #     DASHBOARD_REFRESH   = local.dashboard_refresh
    #     CODERD_SELECTOR     = local.coderd_selector
    #   }
    # }
  }
  default_dashboard_path = "${local.dashboard_config_maps["coder-dashboard-status"].mount_path}/${element(split("/", local.dashboard_config_maps["coder-dashboard-status"].local_path), -1)}"
  # release_name = "coder"
  # chart_name = "coder"
  # namespace = "coder"
}

resource "aws_eip" "grafana" {
  count            = length(local.pub_subs)
  domain           = "vpc"
  public_ipv4_pool = "amazon"
  tags = {
    Name = "grafana-eip-${count.index}"
  }
}

module "monitoring" {

  source = "../../../../../modules/k8s/bootstrap/monitoring"

  chart_version             = var.chart_version
  chart_timeout             = var.chart_timeout
  cluster_name              = var.cluster_name
  cluster_oidc_provider_arn = data.aws_iam_openid_connect_provider.this.arn

  namespace = var.namespace

  lb_class      = "service.k8s.aws/nlb"
  storage_class = "gp3"

  domain_name = var.domain_name

  coder = {
    db = {
      host     = data.aws_db_instance.coder.endpoint
      database = data.aws_db_instance.coder.db_name
      password = var.coder_db_password
      username = var.coder_db_username
    }
    selector = {
      coderd        = "pod=~`coder.*`, pod!~`.*provisioner.*`, namespace=~`(coder)`"
      provisionerd  = "pod=~`coder-provisioner.*`, namespace=~`(coder)`"
      workspaces    = "pod!~`coder.*`, namespace=~`(coder)`"
      ctrl_plane_ns = "coder"
      ext_prov_ns   = "coder"
    }
  }
  grafana = {
    admin = {
      username = var.grafana_admin_username
      password = var.grafana_admin_password
    }
    db = {
      host     = data.aws_db_instance.grafana.endpoint
      database = data.aws_db_instance.grafana.db_name
      password = var.grafana_db_password
      username = var.grafana_db_user
    }
    svc = {
      port = 443
      annots = {
        "service.beta.kubernetes.io/aws-load-balancer-nlb-target-type"      = "ip"
        "service.beta.kubernetes.io/aws-load-balancer-scheme"               = "internet-facing"
        "service.beta.kubernetes.io/aws-load-balancer-attributes"           = "deletion_protection.enabled=false"
        "service.beta.kubernetes.io/aws-load-balancer-healthcheck-protocol" = "TCP"
        "service.beta.kubernetes.io/aws-load-balancer-healthcheck-port"     = 3000
        "service.beta.kubernetes.io/aws-load-balancer-eip-allocations"      = join(",", aws_eip.grafana.*.allocation_id)
        "service.beta.kubernetes.io/aws-load-balancer-subnets"              = join(",", local.pub_subs)
      }
    }
  }
  system_tolerations = [{
    key    = "platform"
    value  = "dedicated"
    effect = "NoSchedule"
  }]
  daemonset_node_selector = {}
  system_affinity = {
    nodeAffinity = {
      requiredDuringSchedulingIgnoredDuringExecution = {
        nodeSelectorTerms = [{
          matchExpressions = [{
            key      = "topology.kubernetes.io/zone"
            operator = "In"
            values   = [for az in local.azs : "${data.aws_region.this.region}${az}"]
            }, {
            key      = "node.coder.io/used-for",
            operator = "In",
            values   = ["platform"]
          }]
        }]
      }
    }
  }
  mount_ssl = {
    enable      = true
    secret_name = kubernetes_manifest.cert.manifest.metadata.name
    mount_path  = "/tmp/grafana/ssl/"
  }
  loki = {
    s3 = {
      chunks_bucket = data.aws_s3_bucket.loki.id
      ruler_bucket  = data.aws_s3_bucket.loki.id
      region        = data.aws_s3_bucket.loki.bucket_region
    }
  }
  dashboards = {
    use_builtins      = false
    default_home_path = local.default_dashboard_path
    config_maps       = local.dashboard_config_maps
  }
}