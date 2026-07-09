terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.17.0"
    }
    kubernetes = {
      source = "hashicorp/kubernetes"
    }
    grafana = {
      source = "grafana/grafana"
    }
  }
}

variable "chart_version" {
    type = string
    default = "0.6.2"
}

variable "chart_timeout" {
    type = number
    default = 300
}

variable "cluster_name" {
  type = string
}

variable "cluster_oidc_provider_arn" {
  type = string
}

variable "namespace" {
  type = string
  default = "coder-observe"
}

variable "dashboards" {
  type = object({
    use_builtins = optional(bool, true)
    default_home_path = optional(string, "")
    config_maps = optional(map(object({
      mount_path = optional(string, "")
      local_path = optional(string, "")
      args = optional(map(string), {})
      read_only = optional(bool, false)
      optional = optional(bool, true)
    })))
  })
  default = {
    use_builtins = true
    config_maps = {}
  }
}

variable "coder" {
    type = object({
        db = object({
            host = string
            password = string
            username = string
            database = string
            sslmode = optional(string, "require")
        })
        selector = object({
            coderd = string
            provisionerd = string
            workspaces = string
            ctrl_plane_ns = string
            ext_prov_ns = string
        })
    })
    sensitive = true
}

variable "grafana" {
  type = object({
    instance_name = optional(string, "Coder Environment")
    admin = object({
        username = string
        password = string
    })
    db = object({
        host = string
        password = string
        username = string
        database = string
        sslmode = optional(string, "require")
    })
    svc = object({
      port = optional(number, 80)
      annots = optional(map(string), {})
    })
    replicas = optional(number, 1)
    tolerations = optional(list(any), [])
    affinity = optional(any, {})
    topology_spread = optional(list(any), [])
    node_selector = optional(map(string), {})
    rsrc = optional(object({
      requests = optional(object({
        cpu = optional(string, "2")
        memory = optional(string, "4Gi")
      }), null)
      limits = optional(object({
        cpu = optional(string, "2")
        memory = optional(string, "4Gi")
      }), null)
    }), {
      requests = null
      limits = null
    })
  })
  sensitive = true
}

variable "loki" {
  type = object({
      s3 = object({
        chunks_bucket = string
        ruler_bucket = string
        region = string
      })
      tolerations = optional(list(any), [])
      affinity = optional(any, {})
      topology_spread = optional(list(any), [])
      node_selector = optional(map(string), {})
      pv = object({
        enabled = optional(bool, true)
        storageClass = optional(string, "gp3")
      })
      rsrc = optional(object({
        requests = optional(object({
          cpu = optional(string, "2")
          memory = optional(string, "4Gi")
        }), null)
        limits = optional(object({
          cpu = optional(string, "2")
          memory = optional(string, "4Gi")
        }), null)
      }), {
        requests = null
        limits = null
      })
  })
}

variable "prometheus" {
  type = object({
    ooo_window = optional(string, "1800s")
    pv = object({
      enabled = optional(bool, true)
      storageClass = optional(string, "gp3")
      size = optional(string, "12Gi")
    })
    tolerations = optional(list(any), [])
    affinity = optional(any, {})
    topology_spread = optional(list(any), [])
    node_selector = optional(map(string), {})
    liveliness = optional(object({
      initial_delay = optional(number, 60)
      timeout = optional(number, 60)
      period = optional(number, 60)
      failure_threshold = optional(number, 10)
    }), {})
    readiness = optional(object({
      initial_delay = optional(number, 60)
      timeout = optional(number, 60)
      period = optional(number, 60)
      failure_threshold = optional(number, 10)
    }), {})
    rsrc = optional(object({
      requests = optional(object({
        cpu = optional(string, "2")
        memory = optional(string, "4Gi")
      }), null)
      limits = optional(object({
        cpu = optional(string, "2")
        memory = optional(string, "4Gi")
      }), null)
    }), {
      requests = null
      limits = null
    })
  })
}

variable "alertmanager" {
  type = object({
    enabled = optional(bool, true)
    pv = object({
      enabled = optional(bool, false)
      storageClass = optional(string, "gp3")
    })
    tolerations = optional(list(any), [])
    affinity = optional(any, {})
    topology_spread = optional(list(any), [])
    node_selector = optional(map(string), {})
    rsrc = optional(object({
      requests = optional(object({
        cpu = optional(string, "2")
        memory = optional(string, "4Gi")
      }), {})
      limits = optional(object({
        cpu = optional(string, "2")
        memory = optional(string, "4Gi")
      }), {})
    }), {
      requests = {}
      limits = {}
    })
  })
}

variable "mount_ssl" {
  type = object({
    enable = optional(bool, true)
    secret_name = optional(string, "ssl-cert")
    mount_path = optional(string, "")
    key_name = optional(string, "tls.key")
    crt_name = optional(string, "tls.crt")
  })
  default = {
    enable = false
    secret_name = "ssl-cert"
    mount_path = ""
    key_name = "tls.key"
    crt_name = "tls.crt"
  }
}

variable "lb_class" {
  type = string
  default = "service.k8s.aws/nlb"
}

variable "tolerations" {
  type = list(any)
  default = []
}

variable "system_tolerations" {
  description = "(Optional) Override if you need to adjust where critical monitoring addons need to be moved."
  type = list(map(any))
  default = [{
    key      = "CriticalAddonsOnly"
    operator = "Exists"
  }]
}

variable "system_affinity" {
  description = "(Optional) Override if you need to adjust where critical monitoring addons need to be moved."
  type = any
  default = {}
}

variable "daemonset_tolerations" {
  description = "(Optional) Override if you need to adjust where monitoring DaemonSets need to be placed."
  type = list(any)
  default = [{
    effect = "NoSchedule"
    operator = "Exists"
  }]
}

variable "daemonset_node_selector" {
  description = "(Optional) Override if you need to adjust where monitoring DaemonSets need to be placed."
  type = map(string)
  default = {}
}

variable "vpc_name" {
  type = string
}

variable "private_subnet_suffix" {
  type    = string
  default = "private"
}

variable "domain_name" {
  type = string
  default = ""
}

variable "acm_certificate_arn" {
  type = string
  default = ""
}

data "aws_region" "this" {}

data "aws_caller_identity" "this" {}

data "aws_vpc" "this" {
  tags = {
    Name = var.vpc_name
  }
}

data "aws_subnets" "private" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.this.id]
  }

  tags = {
    Name = "*${var.private_subnet_suffix}*"
  }
}

locals {
  role_name   = "observability-access"
  policy_name = "ObservabilityAccess-${data.aws_region.this.region}"
}

module "iam-policy" {
  source      = "../../../security/policy"
  name        = local.policy_name
  path        = "/${var.cluster_name}/${data.aws_region.this.region}/"
  description = "Loki S3 policy"
  policy_json = data.aws_iam_policy_document.this.json
}


module "oidc-role" {
  source       = "../../../security/role/access-entry"
  name         = local.role_name
  path         = "/${var.cluster_name}/${data.aws_region.this.region}/"
  cluster_name = var.cluster_name
  policy_arns = {
    "AmazonS3ReadOnlyAccess" = "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess",
    "LokiS3Policy"     = module.iam-policy.policy_arn
    "AmazonPrometheusQueryAccess" = "arn:aws:iam::aws:policy/AmazonPrometheusQueryAccess"
    "AmazonPrometheusRemoteWriteAccess" = "arn:aws:iam::aws:policy/AmazonPrometheusRemoteWriteAccess"
  }
  cluster_policy_arns = {
    "AmazonEKSClusterAdminPolicy" = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy",
  }
  oidc_principals = {
    "${var.cluster_oidc_provider_arn}" = ["system:serviceaccount:*:*"]
  }
  tags = {}
}

resource "kubernetes_namespace_v1" "this" {
    metadata {
        name = var.namespace
    }
}

resource "kubernetes_config_map_v1" "dashboard" {

  for_each = var.dashboards.config_maps

  metadata {
    name = each.key
    namespace = kubernetes_namespace_v1.this.metadata[0].name
  }
  data = {
    (element(split("/", each.value.local_path), -1)) = templatefile(each.value.local_path, each.value.args)
  }
}

resource "random_id" "grafana_server_secret" {
  keepers = {
      # Generate a new secret if the admin password changes
      grafana_admin_username = var.grafana.admin.username
      grafana_admin_password = var.grafana.admin.password
  }
  byte_length = 16
}

locals {
  name = "coder-observe"
  coder_db_host = split(":", var.coder.db.host)[0]
  coder_db_port = split(":", var.coder.db.host)[1]
  grafana_db_host = split(":", var.grafana.db.host)[0]
  # grafana_db_port = split(":", var.grafana.db.host)[1]
}

resource "helm_release" "coder-observe" {
  name             = local.name
  namespace        = kubernetes_namespace_v1.this.metadata[0].name
  chart            = "coder-observability"
  repository       = "https://helm.coder.com/observability"
  create_namespace = false
  upgrade_install  = true
  skip_crds        = false
  wait             = true
  wait_for_jobs    = true
  version          = var.chart_version
  timeout          = var.chart_timeout
  max_history      = 10

  values = [yamlencode({
    global = {
        coder = {
            coderdSelector = var.coder.selector.coderd
            provisionerdSelector = var.coder.selector.provisionerd
            workspacesSelector = var.coder.selector.workspaces
            controlPlaneNamespace = var.coder.selector.ctrl_plane_ns
            externalProvisionersNamespace = var.coder.selector.ext_prov_ns
        }
        postgres = {
            exporter = {
              enabled = true
            }
            hostname = local.coder_db_host
            port = local.coder_db_port
            password = var.coder.db.password
            username = var.coder.db.username
            database = var.coder.db.database
            sslmode = var.coder.db.sslmode
            mountSecret = ""
            affinity = var.prometheus.affinity
        }
        dashboards = {
          enabled = var.dashboards.use_builtins
        }
    }
    prometheus = {
      enabled = true
      # prometheus-node-exporter = {
      #   tolerations = var.daemonset_tolerations
      #   nodeSelector = var.daemonset_node_selector
      # }
      kube-state-metrics = {
        enabled = true
        podAnnotations = {
          "prometheus.io/scrape" = "true"
        }
        affinity = var.prometheus.affinity
        tolerations = var.prometheus.tolerations
      }
      configmapReload = {
        prometheus = {
          enabled = false
          extraArgs = {
            "watch-interval" = "30s"
          }
        }
      }
      server = {
        tsdb = {
          out_of_order_time_window = var.prometheus.ooo_window
        }
        replicaCount = 0
        retention = "1h"
        extraFlags = [
          # "storage.tsdb.wal-compression",
          "web.enable-lifecycle",
          "web.enable-remote-write-receiver"
        ]
        extraArgs = {
          # "storage.tsdb.retention.time" = "1d"
          # "storage.tsdb.min-block-duration" = "2h"
          # "storage.tsdb.max-block-duration" = "2h"
        }
        persistentVolume = { # var.prometheus.pv
          enabled = false
        }
        nodeSelector = var.prometheus.node_selector
        tolerations = var.prometheus.tolerations
        affinity = var.prometheus.affinity
        resources = var.prometheus.rsrc

        livenessProbeInitialDelaySeconds = var.prometheus.liveliness.initial_delay
        livenessProbetimeoutSeconds      = var.prometheus.liveliness.timeout
        livenessProbePeriodSeconds       = var.prometheus.liveliness.period
        livenessProbeFailureThreshold    = var.prometheus.liveliness.failure_threshold

        readinessProbeInitialDelay = var.prometheus.readiness.initial_delay
        readinessProbeTimeout      = var.prometheus.readiness.timeout
        readinessProbePeriodSeconds       = var.prometheus.readiness.period
        readinessProbeFailureThreshold    = var.prometheus.readiness.failure_threshold
      }
      alertmanager = {
        replicas = 0
        enabled = var.alertmanager.enabled
        persistence = var.alertmanager.pv
        nodeSelector = var.alertmanager.node_selector
        tolerations = var.alertmanager.tolerations
        affinity = var.alertmanager.affinity
        # resources = var.alertmanager.rsrc
        resources = {}
      }
    }
    grafana = {
      enabled = false
      # https://github.com/grafana/helm-charts/blob/grafana-7.3.7/charts/grafana/values.yaml#L1313-L1321
      assertNoLeakedSecrets = false
      adminUser = var.grafana.admin.username
      adminPassword = var.grafana.admin.password
      env = {
        GF_SECURITY_DISABLE_INITIAL_ADMIN_CREATION = false
      }
      "grafana.ini" = {
        app_mode = "production"
        auth = {
          sigv4_auth_enabled = true
        }
        "auth.anonymous" = {
          enabled = false
        }
        dashboards = {
          default_home_dashboard_path = var.dashboards.default_home_path
        }
        instance_name = var.grafana.instance_name
        database = {
          host = local.grafana_db_host
          port = 5432
          name = var.grafana.db.database
          username = var.grafana.db.username
          password = "\"\"\"${var.grafana.db.password}\"\"\""
          ssl_mode = var.grafana.db.sslmode
        }
        security = {
          secret_key = random_id.grafana_server_secret.hex
          cookie_secure = true
          cookie_samesite = "lax"
          cookie_domain = var.domain_name
        }
        server = merge(var.mount_ssl.enable ? {
          cert_key = "${trimsuffix(var.mount_ssl.mount_path, "/")}/${var.mount_ssl.key_name}"
          cert_file = "${trimsuffix(var.mount_ssl.mount_path, "/")}/${var.mount_ssl.crt_name}"
          protocol = "https"
          root_url = "https://${var.domain_name}"
        } : {
          protocol = "http"
          root_url = "http://${var.domain_name}"
        }, {
          domain = var.domain_name
          enforce_domain = false
          http_port = 3000
        })
        users = {
          allow_sign_up = false
        }
      }
      nodeSelector = var.grafana.node_selector
      tolerations = var.grafana.tolerations
      affinity = var.grafana.affinity
      replicas = 0 # var.grafana.replicas
      useStatefulSet = true
      resources = var.grafana.rsrc
      readinessProbe = {
        httpGet = {
          scheme = var.mount_ssl.enable ? "HTTPS" : "HTTP"
        }
      }
      livenessProbe = {
        httpGet = {
          scheme = var.mount_ssl.enable ? "HTTPS" : "HTTP"
        }
      }
      persistence = {
        enabled = false
      }
      podAnnotations = {
        "prometheus.io/port" = "3000"
        "prometheus.io/scheme" = var.mount_ssl.enable ? "https" : "http"
        "prometheus.io/scrape" = "true"
      }
      serviceAccount = {
        annotations = {
          "eks.amazonaws.com/role-arn" = module.oidc-role.role_arn
        }
      }
      service = {
        enabled = true
        externalTrafficPolicy = "Cluster"
        internalTrafficPolicy = "Cluster"
        loadBalancerClass = var.lb_class
        port = var.grafana.svc.port
        targetPort = 3000
        type = "LoadBalancer"
        annotations = var.grafana.svc.annots
      }
      extraConfigmapMounts = [ for k, v in var.dashboards.config_maps : {
        name = k
        configMap = kubernetes_config_map_v1.dashboard[k].metadata[0].name
        mountPath = v.mount_path
        readOnly = v.read_only
        optional = v.optional
      } ]
      extraSecretMounts = var.mount_ssl.enable ? [{
        name = var.mount_ssl.secret_name
        mountPath = var.mount_ssl.mount_path
        secretName = var.mount_ssl.secret_name
        readOnly = true
      }] : [] 
      datasources = {
        "datasources.yaml" = {
          datasources = [
            {
              name = "metrics"
              type = "prometheus"
              url = aws_prometheus_workspace.this.prometheus_endpoint
              access = "proxy"
              isDefault = true
              editable = false
              timeout = 905
              uid = "prometheus"
              jsonData = {
                sigV4AuthType = "default"
                httpMethod = "POST"
                sigV4Auth = true
                sigV4Region = data.aws_region.this.region
              }
            },      
            {
              name      = "pyroscope"
              type      = "grafana-pyroscope-datasource"
              url       = "http://pyroscope.${var.namespace}.svc:4040"
              isDefault = false
              editable  = false
              access    = "proxy"
              timeout   = 905
              uid       = "pyroscope"
            },
            {
              name      = "traces"
              type      = "tempo"
              url       = "http://tempo.${var.namespace}.svc:3200"
              access    = "proxy"
              isDefault = false
              editable  = false
              timeout   = 905
              uid       = "tempo"
            }
          ]
        }
      }
    }
    grafana-agent = {
      enabled = false
    }
    sqlExporter = {
      enabled = false
    }
    runbookViewer = {
      enabled = false
    }
    loki = {
      loki = {
        storage = {
          bucketNames = {
            chunks = var.loki.s3.chunks_bucket
            ruler = var.loki.s3.ruler_bucket
          }
          s3 = {
            region = var.loki.s3.region
          }
          type = "s3"
        }
        rulerConfig = {
          remote_write = {
            enabled = true
            clients = {
              fake = {
                url = "${aws_prometheus_workspace.this.prometheus_endpoint}/api/v1/remote_write"
              }
            }
          }
        }
      }
      lokiCanary = {
        tolerations = var.daemonset_tolerations
        nodeSelector = var.daemonset_node_selector
      }
      backend = {
        replicas = 1
        tolerations = var.loki.tolerations
        affinity = var.loki.affinity
        persistence = {
          volumeClaimsEnabled = false
          # storageClass = var.storage_class
        }
      }
      resultsCache = {
        replicas = 1
        tolerations = var.loki.tolerations
        affinity = var.loki.affinity
      }
      chunksCache = {
        replicas = 1
        tolerations = var.loki.tolerations
        affinity = var.loki.affinity
        persistence = var.loki.pv
      }
      write = {
        replicas = 1
        tolerations = var.loki.tolerations
        affinity = var.loki.affinity
        persistence = {
          volumeClaimsEnabled = false
          # storageClass = var.storage_class
        }
      }
      read = {
        replicas = 1
        tolerations = var.loki.tolerations
        affinity = var.loki.affinity
        podAnnotatiosn = {
          "prometheus.io/scrape" = "true"
        }
      }
      minio = {
        enabled = false
        # tolerations = var.system_tolerations
      }
      gateway = {
        replicas = 1
        tolerations = var.loki.tolerations
        affinity = var.loki.affinity
        podAnnotatiosn = {
          "prometheus.io/scrape" = "true"
        }
        service = {
          type = "LoadBalancer"
          annotations = {
            "service.beta.kubernetes.io/aws-load-balancer-nlb-target-type" = "ip"
            "service.beta.kubernetes.io/aws-load-balancer-scheme" = "internal"
          }
        }
      }
      serviceAccount = {
        create = true
        annotations = {
          "eks.amazonaws.com/role-arn" = module.oidc-role.role_arn
        }
      }
    }
  })]
}

data "aws_iam_policy_document" "grafana-sts" {
  statement {
    effect    = "Allow"
    principals {
      type = "Service"
      identifiers = ["grafana.amazonaws.com"]
    }
    actions   = ["sts:AssumeRole"]
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values = ["${data.aws_caller_identity.this.account_id}"]
    }
    condition {
      test     = "StringLike"
      variable = "aws:SourceArn"
      values = ["arn:aws:grafana:${data.aws_region.this.region}:${data.aws_caller_identity.this.account_id}:/workspaces/*"]
    }
  }
}

resource "aws_iam_role" "grafana" {
  name = "${local.name}-grafana"
  path = "/"
  assume_role_policy = data.aws_iam_policy_document.grafana-sts.json
}

data "aws_iam_policy_document" "grafana" {
  statement {
    effect    = "Allow"
    actions   = [
      "aps:ListWorkspaces",
      "aps:DescribeWorkspace",
      "aps:QueryMetrics",
      "aps:GetLabels",
      "aps:GetSeries",
      "aps:GetMetricMetadata"
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "policy" {
  name        = "${local.name}-grafana"
  description = "AWS Managed Grafana Policy"
  policy      = data.aws_iam_policy_document.grafana.json
}

resource "aws_iam_role_policy_attachment" "grafana" {

  for_each = {
    "${local.name}-grafana" = aws_iam_policy.policy.arn
    "AmazonGrafanaCloudWatchAccess" = "arn:aws:iam::aws:policy/service-role/AmazonGrafanaCloudWatchAccess"
  }

  role       = aws_iam_role.grafana.name
  policy_arn = each.value
}

resource "aws_security_group" "grafana" {
  vpc_id      = data.aws_vpc.this.id
  name        = "${local.name}-grafana"
  description = "SG for Grafana - All Egress traffic"
  tags = {
    Name = "Customer-Managed AWS Managed Grafana"
  }
}

resource "aws_vpc_security_group_egress_rule" "grafana" {
  security_group_id = aws_security_group.grafana.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = -1
}

locals {
  # Root, Coder, Customer
  ous = ["r-4vw4", "ou-4vw4-avnmq38g", "ou-4vw4-2qki2hxj"]
  admin_iam_identity_ids = [
    "24c85468-90e1-70c7-3498-bc5695b7c6f0",  # Jullian
  ]
  viewer_group_iam_identity_ids = [
    "a498a458-b0c1-70a8-face-e9480207b880"
  ]
  viewer_iam_identity_ids = [
    "d4a80408-70f1-70a0-d637-d3372eb29d29", # Dave Ahr
    "743804f8-30d1-705d-9ed9-d1905cbac291", # Michael Patterson
    "d4a8a458-c041-70eb-a4c4-94db19a67d83", # Matt Colton,
    "347844f8-e031-70f5-78cc-7ebcdeec102c", # Jakub
  ]
}

data "aws_ssoadmin_instances" "this" {
  region = "us-east-1"
}

data "aws_identitystore_group" "aws_administrator" {
  identity_store_id = one(data.aws_ssoadmin_instances.this.identity_store_ids)
  region = "us-east-1"

  alternate_identifier {
    unique_attribute {
      attribute_path  = "DisplayName"
      attribute_value = "CoderCSAWSAdmin"
    }
  }
}

data "aws_identitystore_group_memberships" "aws_admins" {
  identity_store_id = one(data.aws_ssoadmin_instances.this.identity_store_ids)
  region = "us-east-1"
  group_id          = data.aws_identitystore_group.aws_administrator.group_id
}

resource "aws_grafana_workspace" "this" {

  name = local.name

  account_access_type = "ORGANIZATION"
  organizational_units = local.ous
  authentication_providers = ["AWS_SSO"]
  permission_type = "CUSTOMER_MANAGED"
  region = data.aws_region.this.region
  data_sources = ["PROMETHEUS", "CLOUDWATCH"]
  grafana_version = "10.4"
  role_arn = aws_iam_role.grafana.arn
  
  vpc_configuration {
    security_group_ids = [
      aws_security_group.grafana.id
    ]
    subnet_ids = toset(concat(
      data.aws_subnets.private.ids
    ))
  }
}

resource "aws_grafana_role_association" "admins" {
  role         = "ADMIN"
  user_ids     = local.admin_iam_identity_ids
  group_ids    = [data.aws_identitystore_group.aws_administrator.group_id]
  workspace_id = aws_grafana_workspace.this.id
}

resource "aws_grafana_workspace_service_account" "admin" {
  name         = "admin"
  grafana_role = "ADMIN"
  workspace_id = aws_grafana_workspace.this.id
}

resource "random_pet" "token_name" {}

resource "aws_grafana_workspace_service_account_token" "admin" {
  name               = random_pet.token_name.id
  service_account_id = aws_grafana_workspace_service_account.admin.service_account_id
  seconds_to_live    = 2591999 # 30 days
  workspace_id       = aws_grafana_workspace.this.id

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_grafana_role_association" "viewer" {
  role         = "VIEWER"
  user_ids     = local.viewer_iam_identity_ids
  group_ids    = [data.aws_identitystore_group.aws_administrator.group_id]
  workspace_id = aws_grafana_workspace.this.id
}

resource "aws_grafana_workspace_service_account" "viewer" {
  name         = "viewer"
  grafana_role = "VIEWER"
  workspace_id = aws_grafana_workspace.this.id
}

resource "aws_prometheus_workspace" "this" {
  alias = local.name
}

# resource "aws_prometheus_rule_group_namespace" "coder_alerts" {
#   name         = "coder-alerts"
#   workspace_id = aws_prometheus_workspace.coder.id
#   data         = file("${path.module}/alert-rules.yaml")
# }

resource "aws_cloudfront_distribution" "grafana" {
  enabled             = true
  aliases             = [var.domain_name]
  default_root_object = ""
  price_class = "PriceClass_100"

  origin {
    domain_name = aws_grafana_workspace.this.endpoint
    origin_id   = "ALB-Grafana"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "ALB-Grafana"
    
    forwarded_values {
      query_string = true
      cookies {
        forward = "all"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn = var.acm_certificate_arn
    ssl_support_method  = "sni-only"
  }
}

provider "grafana" {
  url  = "https://${aws_grafana_workspace.this.endpoint}"
  auth = aws_grafana_workspace_service_account_token.admin.key
  retries = 100
  retry_wait = 10
  retry_status_codes = toset(["429","5xx"])
}

resource "grafana_data_source" "cloudwatch" {
  type = "cloudwatch"
  name = "cloudwatch"
  access_mode = "proxy"

  json_data_encoded = jsonencode({
    defaultRegion = "${data.aws_region.this.region}"
    authType      = "default"
  })
}

resource "grafana_data_source" "prometheus" {
  type                = "prometheus"
  name                = "prometheus"
  url                 = aws_prometheus_workspace.this.prometheus_endpoint
  access_mode = "proxy"
  is_default = true

  basic_auth_enabled  = false
  json_data_encoded = jsonencode({
    sigV4AuthType = "default"
    httpMethod = "POST"
    sigV4Auth = true
    sigV4Region = data.aws_region.this.region
  })
}

data "kubernetes_service_v1" "loki-gateway" {

  depends_on = [helm_release.coder-observe]

  metadata {
    name = "loki-gateway"
    namespace = kubernetes_namespace_v1.this.metadata[0].name
  }
}

resource "grafana_data_source" "loki-gateway" {
  type = "loki"
  name = "loki"
  access_mode = "proxy"
  url = "http://${data.kubernetes_service_v1.loki-gateway.status[0].load_balancer[0].ingress[0].hostname}"
}

resource "grafana_data_source" "postgres" {
  type = "postgres"
  name = "postgres"
  url       = "${local.coder_db_host}:${local.coder_db_port}"
  access_mode = "proxy"
  is_default = false

  username = var.grafana.db.username

  json_data_encoded = jsonencode({
    database        = "coder"
    sslmode         = "require"
    postgresVersion = "903"  # Set your specific version: https://registry.terraform.io/providers/grafana/grafana/1.28.2/docs/resources/data_source#postgres_version-1
    timescaledb     = false # Toggle true if using TimescaleDB
  })

  secure_json_data_encoded = jsonencode({
    password = var.grafana.db.password
  })
}

resource "grafana_dashboard" "this" {
  for_each = var.dashboards.config_maps
  config_json = templatefile(each.value.local_path, each.value.args)
}

resource "grafana_organization_preferences" "this" {
  home_dashboard_uid = grafana_dashboard.this["coder-dashboard-status"].uid
  theme = "system"
  timezone = "browser"
  week_start = "monday"
}

resource "kubernetes_config_map_v1" "collector-config" {

  metadata {
    name = "collector-config"
    namespace = var.namespace
    labels = {}
    annotations = {}
  }
  data = {
    "config.river" = templatefile("${path.module}/collector-config.river", {
      LOKI_ENDPOINT = "http://loki-gateway.${var.namespace}.svc/loki/api/v1/push"
      AWS_PROMETHEUS_ENDPOINT = "${trimsuffix(aws_prometheus_workspace.this.prometheus_endpoint, "/")}/api/v1/remote_write"
      AWS_PROMETHEUS_REGION = data.aws_region.this.region
    })
  }
}

resource "kubernetes_service_account_v1" "grafana-agent" {
  metadata {
    name = "grafana-agent"
    namespace = kubernetes_namespace_v1.this.metadata[0].name
    annotations = {
      "eks.amazonaws.com/role-arn" = module.oidc-role.role_arn
    }
  }
  automount_service_account_token = true
}

resource "helm_release" "grafana-agent" {
  name = "grafana-agent"
  namespace = kubernetes_namespace_v1.this.metadata[0].name
  chart = "grafana-agent"
  repository = "https://grafana.github.io/helm-charts"
  create_namespace = false
  upgrade_install  = true
  skip_crds        = false
  wait             = true
  wait_for_jobs    = true
  version          = "0.37.0"
  timeout          = 600

  values = [yamlencode({
    agent = {
      mode = "flow"

      configMap = {
        name   = kubernetes_config_map_v1.collector-config.metadata[0].name
        key    = "config.river"
        create = false
      }

      clustering = {
        enabled = true
      }

      extraArgs = [
        "--disable-reporting=true"
      ]

      mounts = {
        varlog           = true
        dockercontainers = true
      }
    }

    controller = {
      type = "daemonset"
      podAnnotations = {
        "prometheus.io/scheme" = "http"
        "prometheus.io/scrape" = "true"
      }
      tolerations = var.daemonset_tolerations
      nodeSelector = var.daemonset_node_selector
      updateStrategy = {
        type = "RollingUpdate"
        rollingUpdate = {
          maxSurge = 0
          maxUnavailable = "100%"
        }
      }
    }

    serviceAccount = {
      name = kubernetes_service_account_v1.grafana-agent.metadata[0].name
      create = false
    }

    crds = {
      create = false
    }

    withOTLPReceiver = false

    discovery = <<-EOT
      // Discover k8s nodes
      discovery.kubernetes "nodes" {
        role = "node"
      }

      // Discover k8s pods
        discovery.kubernetes "pods" {
          role = "pod"
          selectors {
            role  = "pod"
            field = "spec.nodeName=" + env("HOSTNAME")
          }
        }
    EOT

    extraBlocks             = ""
    podMetricsRelabelRules  = ""
    podLogsRelabelRules     = ""

    commonRelabellings = <<-EOF
      rule {
        source_labels = ["__meta_kubernetes_namespace"]
        target_label  = "namespace"
      }
      rule {
        source_labels = ["__meta_kubernetes_pod_name"]
        target_label  = "pod"
      }
      // coalesce the following labels and pick the first value; we'll use this to define the "job" label
      rule {
        source_labels  = ["__meta_kubernetes_pod_label_app_kubernetes_io_component", "app", "__meta_kubernetes_pod_container_name"]
        separator      = "/"
        target_label   = "__meta_app"
        action         = "replace"
        regex          = "^/*([^/]+?)(?:/.*)?$" // split by the delimiter if it exists, we only want the first one
        replacement    = "$1"
      }
      rule {
        source_labels = ["__meta_kubernetes_namespace", "__meta_kubernetes_pod_label_app_kubernetes_io_name", "__meta_app"]
        separator     = "/"
        target_label  = "job"
      }
      rule {
        source_labels = ["__meta_kubernetes_pod_container_name"]
        target_label  = "container"
      }
      rule {
        regex   = "__meta_kubernetes_pod_label_(statefulset_kubernetes_io_pod_name|controller_revision_hash)"
        action  = "labeldrop"
      }
      rule {
        regex   = "pod_template_generation"
        action  = "labeldrop"
      }
      rule {
        source_labels = ["__meta_kubernetes_pod_phase"]
        regex = "Pending|Succeeded|Failed|Completed"
        action = "drop"
      }
      rule {
        source_labels = ["__meta_kubernetes_pod_node_name"]
        action = "replace"
        target_label = "node"
      }
      rule {
        action = "labelmap"
        regex = "__meta_kubernetes_pod_annotation_prometheus_io_param_(.+)"
        replacement = "__param_$1"
      }
    EOF
  })]
}

output "namespace" {
  value = kubernetes_namespace_v1.this.metadata[0].name
}