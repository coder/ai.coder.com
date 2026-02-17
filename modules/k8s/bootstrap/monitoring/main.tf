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

variable "coder" {
    type = object({
        db = object({
            host = string
            port = optional(number, 5432)
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
        admin = object({
            username = string
            password = string
        })
        db = object({
            host = string
            port = optional(number, 5432)
            password = string
            username = string
            database = string
            sslmode = optional(string, "require")
        })
        svc = object({
            annots = map(string)
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
    })
}

variable "domain_name" {
    type = string
}

variable "lb_class" {
  type = string
  default = "service.k8s.aws/nlb"
}

variable "tolerations" {
  type = list(map(any))
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

variable "daemonset_tolerations" {
  description = "(Optional) Override if you need to adjust where monitoring DaemonSets need to be placed."
  type = list(map(any))
  default = [{
    effect = "NoSchedule"
    operator = "Exists"
  }]
}

data "aws_s3_bucket" "loki" {
  bucket = "${var.cluster_name}-grafana"
}

data "aws_region" "this" {}

data "aws_caller_identity" "this" {}

locals {
  region      = data.aws_region.this.region
  account_id  = data.aws_caller_identity.this.account_id
  policy_name = "loki-s3-access"
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
        name = "coder-observe"
    }
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
            hostname = var.coder.db.host
            port = var.coder.db.port
            password = var.coder.db.password
            username = var.coder.db.username
            database = var.coder.db.database
            sslmode = var.coder.db.sslmode
            mountSecret = ""
        }
    }
    prometheus = {
      server = {
        tolerations = var.system_tolerations
        persistentVolume = {
          enabled = true
          storageClassName = var.storage_class
        }
      }
      alertmanager = {
        enabled = true
        tolerations = var.system_tolerations
        persistence = {
          enabled = true
          storageClass = var.storage_class
        }
      }
    }
    grafana = {
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
        instance_name = "Coder Environment"
        database = {
            url = "postgres://${var.grafana.db.username}:${var.grafana.db.password}@${var.grafana.db.host}:${var.grafana.db.port}/${var.grafana.db.database}"
            ssl_mode = var.grafana.db.sslmode
        }
        server = {
            root_url = "https://${var.domain_name}"
            domain = var.domain_name
            enforce_domain = true
            http_port = 3000
            protocol = "http"
        }
        users = {
            allow_sign_up = false
        }
      }
      replicas = 2
      useStatefulSet = true
      readinessProbe = {
        httpGet = {
          scheme = "HTTP"
        }
      }
      livenessProbe = {
        httpGet = {
          scheme = "HTTP"
        }
      }
      persistence = {
        enabled = false
      }
      podAnnotations = {
        "prometheus.io/port" = "3000"
        "prometheus.io/scheme" = "http"
        "prometheus.io/scrape" = "true"
      }
      service = {
        annotations = var.grafana.svc.annots
        enabled = true
        externalTrafficPolicy = "Cluster"
        internalTrafficPolicy = "Cluster"
        loadBalancerClass = var.lb_class
        port = 443
        targetPort = 3000
        type = "LoadBalancer"
      }
      tolerations = var.system_tolerations
    }
    grafana-agent = {
        enabled = true
        controller = {
          tolerations = var.daemonset_tolerations
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
        controller = {
            type = "daemonset"
            podAnnotations = {
                "prometheus.io/scheme" = "http"
                "prometheus.io/scrape" = "true"
            }
        }
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
      }
      backend = {
        tolerations = var.system_tolerations
        persistence = {
          volumeClaimsEnabled = false
          # storageClass = var.storage_class
        }
      }
      resultsCache = {
        tolerations = var.system_tolerations
      }
      chunksCache = {
        tolerations = var.system_tolerations
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