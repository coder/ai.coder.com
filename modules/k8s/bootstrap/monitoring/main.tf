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

variable "storage_class" {
  type = string
  default = ""
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
        affinity = optional(map(any), {})
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

variable "domain_name" {
    type = string
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

data "aws_region" "this" {}

data "aws_caller_identity" "this" {}

locals {
  role_name   = "loki-s3-access"
}

module "oidc-role" {
  source       = "../../../security/role/access-entry"
  name         = local.role_name
  path         = "/${var.cluster_name}/${data.aws_region.this.region}/"
  cluster_name = var.cluster_name
  policy_arns = {
    "AmazonEKSLoadBalancingPolicy" = "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess",
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
  coder_db_host = split(":", var.coder.db.host)[0]
  coder_db_port = split(":", var.coder.db.host)[1]
  grafana_db_host = split(":", var.grafana.db.host)[0]
  grafana_db_port = split(":", var.grafana.db.host)[1]
}

resource "helm_release" "coder-observe" {
  name             = "coder-observe"
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
            hostname = local.coder_db_host
            port = local.coder_db_port
            password = var.coder.db.password
            username = var.coder.db.username
            database = var.coder.db.database
            sslmode = var.coder.db.sslmode
            mountSecret = ""
        }
        dashboards = {
          enabled = var.dashboards.use_builtins
        }
    }
    prometheus = {
      # prometheus-node-exporter = {
      #   tolerations = var.daemonset_tolerations
      #   nodeSelector = var.daemonset_node_selector
      # }
      server = {
        tolerations = var.system_tolerations
        affinity = var.system_affinity
        persistentVolume = {
          enabled = true
          storageClassName = var.storage_class
        }
      }
      alertmanager = {
        enabled = true
        tolerations = var.system_tolerations
        affinity = var.system_affinity
        persistence = {
          enabled = true
          storageClass = var.storage_class
        }
      }
    }
    grafana = {
      # https://github.com/grafana/helm-charts/blob/grafana-7.3.7/charts/grafana/values.yaml#L1313-L1321
      assertNoLeakedSecrets = false
      adminUser = var.grafana.admin.username
      adminPassword = var.grafana.admin.password
      env = {
        GF_SECURITY_DISABLE_INITIAL_ADMIN_CREATION = false
      }
      "grafana.ini" = {
        app_mode = "production"
        "auth.anonymous" = {
          enabled = false
        }
        dashboards = {
          default_home_dashboard_path = var.dashboards.default_home_path
        }
        instance_name = var.grafana.instance_name
        database = {
          host = local.grafana_db_host
          port = local.grafana_db_port
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
      affinity = var.system_affinity
      replicas = 1
      useStatefulSet = true
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
      tolerations = var.system_tolerations
      affinity = var.system_affinity
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
    }
    grafana-agent = {
        enabled = true
        controller = {
            type = "daemonset"
            podAnnotations = {
                "prometheus.io/scheme" = "http"
                "prometheus.io/scrape" = "true"
            }
            tolerations = var.daemonset_tolerations
            nodeSelector = var.daemonset_node_selector
        }
        discovery = <<-EOF
            // Discover k8s nodes
            discovery.kubernetes "nodes" {
                role = "node"
            }

            // Discover k8s pods
            discovery.kubernetes "pods" {
                role = "pod"
                selectors {
                    role  = "pod"
                }
            }
        EOF
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
                replacement    = "$${1}"
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
      }
      lokiCanary = {
        tolerations = var.daemonset_tolerations
        nodeSelector = var.daemonset_node_selector
      }
      backend = {
        tolerations = var.system_tolerations
        affinity = var.system_affinity
        persistence = {
          volumeClaimsEnabled = false
          # storageClass = var.storage_class
        }
      }
      resultsCache = {
        tolerations = var.system_tolerations
        affinity = var.system_affinity
      }
      chunksCache = {
        tolerations = var.system_tolerations
        affinity = var.system_affinity
        persistence = {
          enabled = true
          storageClass = var.storage_class
        }
      }
      minio = {
        enable = false
        # tolerations = var.system_tolerations
      }
      write = {
        tolerations = var.system_tolerations
        affinity = var.system_affinity
        persistence = {
          volumeClaimsEnabled = false
          # storageClass = var.storage_class
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

output "namespace" {
  value = kubernetes_namespace_v1.this.metadata[0].name
}