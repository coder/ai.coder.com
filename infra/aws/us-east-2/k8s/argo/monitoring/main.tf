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

provider "kubernetes" {
  host                   = data.aws_eks_cluster.this.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.this.token
}

data "aws_db_instance" "coder" {
  db_instance_identifier = var.coder_db_rds_id
}

data "aws_s3_bucket" "loki" {
  region = var.loki_s3_bucket_region
  bucket = var.loki_s3_bucket_name
}

locals {
  role_name   = "coder-observability"
  policy_name = "ObservabilityAccess-${var.region}"
  namespace   = "coder-observability"
  azs         = slice(var.azs, 0, 1)
}

module "loki-policy" {
  source      = "../../../../../../modules/security/policy"
  name        = local.policy_name
  path        = "/${var.cluster_name}/${var.region}/"
  description = "Loki S3 policy"
  policy_json = data.aws_iam_policy_document.loki.json
}

module "oidc-role" {
  source       = "../../../../../../modules/security/role/access-entry"
  name         = local.role_name
  path         = "/${var.cluster_name}/${var.region}/"
  cluster_name = var.cluster_name
  policy_arns = {
    "AmazonS3ReadOnlyAccess"            = "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess",
    "LokiS3Policy"                      = module.loki-policy.policy_arn
    "AmazonPrometheusQueryAccess"       = "arn:aws:iam::aws:policy/AmazonPrometheusQueryAccess"
    "AmazonPrometheusRemoteWriteAccess" = "arn:aws:iam::aws:policy/AmazonPrometheusRemoteWriteAccess"
  }
  cluster_policy_arns = {
    "AmazonEKSClusterAdminPolicy" = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy",
  }
  oidc_principals = {
    "${data.aws_iam_openid_connect_provider.this.arn}" = ["system:serviceaccount:*:*"]
  }
  tags = {}
}

locals {
  loki_tolerations = [{
    key    = "platform"
    value  = "observability-platform"
    effect = "NoSchedule"
  }]
  prometheus_tolerations = [{
    key    = "platform"
    value  = "prometheus"
    effect = "NoSchedule"
  }]
  prometheus_affinity = {
    nodeAffinity = {
      requiredDuringSchedulingIgnoredDuringExecution = {
        nodeSelectorTerms = [{
          matchExpressions = [{
            key      = "topology.kubernetes.io/zone"
            operator = "In"
            values   = [for az in local.azs : "${var.region}${az}"]
            }, {
            key      = "node.coder.io/used-for"
            operator = "In"
            values   = ["prometheus"]
            }, {
            key      = "beta.kubernetes.io/arch"
            operator = "In"
            values   = ["arm64"]
          }]
        }]
      }
    }
  }
  daemonset_tolerations = [{
    effect   = "NoSchedule"
    operator = "Exists"
  }]
  shared_tolerations = [{
    key    = "platform"
    value  = "observability-platform"
    effect = "NoSchedule"
  }]
  shared_affinity = {
    nodeAffinity = {
      requiredDuringSchedulingIgnoredDuringExecution = {
        nodeSelectorTerms = [{
          matchExpressions = [{
            key      = "topology.kubernetes.io/zone"
            operator = "In"
            values   = [for az in local.azs : "${var.region}${az}"]
            }, {
            key      = "node.coder.io/used-for",
            operator = "In",
            values   = ["observability-platform"]
            }, {
            key      = "beta.kubernetes.io/arch"
            operator = "In"
            values   = ["arm64"]
          }]
        }]
      }
    }
  }
  prometheus_annotation = {
    "prometheus.io/scrape" = "true"
  }
  grafana_agent_config = templatefile("${path.module}/collector-config.river", {
    LOKI_ENDPOINT           = "http://coder-observability-loki.${local.namespace}.svc:3100/loki/api/v1/push"
    AWS_PROMETHEUS_ENDPOINT = "${trimsuffix(var.prometheus_endpoint, "/")}/api/v1/remote_write"
    AWS_PROMETHEUS_REGION   = var.region
  })
}

data "aws_secretsmanager_secret" "grafana" {
  name = "rds-${var.grafana_db_user}"
}

resource "kubernetes_manifest" "coder-observability" {

  wait {
    fields = {
      "status.health.status" = "Healthy"
      # "status.sync.status"   = "Synced"
    }
  }

  timeouts {
    create = "5m"
    update = "5m"
    delete = "30s"
  }

  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name        = "${var.region}.coder-observability"
      namespace   = "argocd"
      labels      = {}
      annotations = {}
    }
    spec = {
      project = "default"
      source = {
        repoURL        = "https://github.com/coder/ai.coder.com"
        path           = "charts/coder-observability"
        targetRevision = "main"
        helm = {
          releaseName = "coder-observability"
          values = yamlencode({
            extra = {
              secretStore = {
                labels      = {}
                annotations = {}
                aws = {
                  region = var.region
                }
              }
            }
            kube-state-metrics = {
              enabled        = true
              tolerations    = local.shared_tolerations
              affinity       = local.shared_affinity
              podAnnotations = merge({}, local.prometheus_annotation)
            }
            postgres-exporter = {
              enabled     = true
              tolerations = local.shared_tolerations
              affinity    = local.shared_affinity
              config = {
                extraArgs = [
                  "--collector.long_running_transactions"
                ]
                datasource = {
                  host    = data.aws_db_instance.coder.address
                  user    = var.grafana_db_user
                  port    = "5432"
                  sslmode = "require"
                  passwordSecret = {
                    secretArn = data.aws_secretsmanager_secret.grafana.arn
                    name      = "coder-observability.rds.grafana.secret"
                  }
                  database = data.aws_db_instance.coder.db_name
                }
              }
              annotations = merge({
                "prometheus.io/port" = "9187"
              }, local.prometheus_annotation)
            }
            node-exporter = {
              enabled        = true
              tolerations    = local.daemonset_tolerations
              podAnnotations = merge({}, local.prometheus_annotation)
            }
            grafana-agent = {
              enabled = true

              serviceAccount = {
                create = true
                annotations = {
                  "eks.amazonaws.com/role-arn" = module.oidc-role.role_arn
                }
              }

              controller = {
                tolerations = local.daemonset_tolerations
                podAnnotations = merge({
                  "checksum/config" = sha256(local.grafana_agent_config)
                }, local.prometheus_annotation)
              }

              agent = {
                configMap = {
                  content = local.grafana_agent_config
                }
              }
            }

            loki = {
              # Loki in Monolithic Mode.
              # https://grafana.com/docs/loki/latest/setup/install/helm/install-monolithic/
              # https://grafana.com/docs/loki/latest/setup/install/helm/install-monolithic/#object-storage-configuration
              # https://grafana.com/docs/loki/latest/setup/install/helm/deployment-guides/aws/#loki-helm-chart-configuration
              enabled        = true
              deploymentMode = "SingleBinary"
              loki = {
                auth_enabled = false
                commonConfig = {
                  replication_factor = 1
                }
                schemaConfig = {
                  configs = [{
                    from         = "2024-04-01"
                    store        = "tsdb"
                    object_store = "s3"
                    schema       = "v13"
                    index = {
                      prefix = "loki_index_"
                      period = "24h"
                    }
                  }]
                }
                useTestSchema = false
                pattern_ingester = {
                  enabled = true
                }
                limits_config = {
                  allow_structured_metadata = true
                  volume_enabled            = true
                  retention_period          = "672h" # 28 days retention
                }
                storage_config = {
                  aws = {
                    region           = var.loki_s3_bucket_region
                    bucketnames      = data.aws_s3_bucket.loki.id
                    s3forcepathstyle = false
                  }
                }
                storage = {
                  bucketNames = {
                    chunks = data.aws_s3_bucket.loki.id
                    ruler  = data.aws_s3_bucket.loki.id
                  }
                  s3 = {
                    region = var.loki_s3_bucket_region
                  }
                  type = "s3"
                }
                compactor = {
                  retention_enabled    = true
                  delete_request_store = "s3"
                }
                rulerConfig = {
                  enable_api = true
                  remote_write = {
                    enabled = true
                    clients = {
                      fake = {
                        url = "${trimsuffix(var.prometheus_endpoint, "/")}/api/v1/remote_write"
                      }
                    }
                  }
                }
              }
              minio = {
                enabled = false
              }
              singleBinary = {
                replicas    = 1
                tolerations = local.shared_tolerations
                affinity    = local.shared_affinity
                persistence = {
                  storageClass = "gp3-automode"
                  accessModes = [
                    "ReadWriteOnce"
                  ]
                  size = "30Gi"
                }
                service = {
                  type = "LoadBalancer"
                  annotations = {
                    "service.beta.kubernetes.io/aws-load-balancer-nlb-target-type" = "ip"
                    "service.beta.kubernetes.io/aws-load-balancer-scheme"          = "internal"
                  }
                }
                podAnnotations = merge({}, local.prometheus_annotation)
              }
              lokiCanary = {
                tolerations = local.daemonset_tolerations
                annotations = merge({}, local.prometheus_annotation)
              }
              write = {
                replicas    = 0
                tolerations = local.shared_tolerations
                affinity    = local.shared_affinity
                persistence = {
                  volumeClaimsEnabled = false
                }
              }
              read = {
                replicas    = 0
                tolerations = local.shared_tolerations
                affinity    = local.shared_affinity
              }
              backend = {
                replicas = 0
                tolerations = [{
                  key    = "platform"
                  value  = "observability-platform"
                  effect = "NoSchedule"
                }]
                affinity = local.shared_affinity
                persistence = {
                  volumeClaimsEnabled = false
                }
              }
              resultsCache = {
                replicas    = 1
                tolerations = local.shared_tolerations
                affinity    = local.shared_affinity
              }
              chunksCache = {
                replicas    = 1
                tolerations = local.shared_tolerations
                affinity    = local.shared_affinity
                persistence = {
                  enabled      = true
                  storageClass = "gp3-automode"
                }
                resources = {
                  requests = {
                    memory = "1Gi"
                  }
                  limits = {
                    memory = "4Gi"
                  }
                }
              }
              ingester = {
                replicas = 0
              }
              querier = {
                replicas = 0
              }
              queryFrontend = {
                replicas = 0
              }
              queryScheduler = {
                replicas = 0
              }
              distributor = {
                replicas = 0
              }
              compactor = {
                replicas = 0
              }
              indexGateway = {
                replicas = 0
              }
              bloomPlanner = {
                replicas = 0
              }
              bloomBuilder = {
                replicas = 0
              }
              bloomGateway = {
                replicas = 0
              }
              gateway = {
                replicas    = 0
                enabled     = false
                tolerations = local.shared_tolerations
                affinity    = local.shared_affinity
                basicAuth = {
                  enabled = false
                }
                service = {
                  type = "LoadBalancer"
                  annotations = {
                    "service.beta.kubernetes.io/aws-load-balancer-nlb-target-type" = "ip"
                    "service.beta.kubernetes.io/aws-load-balancer-scheme"          = "internal"
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
          })
        }
      }
      destination = {
        server    = data.aws_eks_cluster.this.arn
        namespace = local.namespace
      }
      syncPolicy = {
        automated = {
          prune = true
        }
        syncOptions = [
          "CreateNamespace=true",
          "Delete=false"
        ]
      }
    }
  }
}