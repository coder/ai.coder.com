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

data "aws_eks_cluster" "controller" {
  region = "us-east-2"
  name = var.cluster_name
}

data "aws_eks_cluster_auth" "controller" {
  region = "us-east-2"
  name = var.cluster_name
}

data "aws_region" "this" {}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.controller.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.controller.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.controller.token
}

data "http" "login" {
  url    = "${var.coder_access_url}/api/v2/users/login"
  method = "POST"
  request_headers = {
    Accept = "application/json"
  }
  request_body = jsonencode({
    email    = var.coder_admin_email
    password = var.coder_admin_password
  })

  retry {
    attempts     = 5
    min_delay_ms = (5 * 1000) # 5 seconds 
  }
}

provider "coderd" {
  url   = var.coder_access_url
  token = jsondecode(data.http.login.response_body).session_token
}

locals {
  azs          = slice(var.azs, 0, 1)
  pub_subs     = [for az in local.azs : "${var.vpc_name}-public-${data.aws_region.this.region}${az}"]
  release_name = "coder"
  chart_name   = "coder"
  namespace    = "coder"

  common_name           = trimprefix(trimprefix(var.coder_proxy_url, "https://"), "http://")
  wildcard_name         = trimprefix(trimprefix(var.coder_proxy_wildcard_url, "https://"), "http://")
  ssl_vol_friendly_name = replace(local.common_name, ".", "-")
}

resource "coderd_workspace_proxy" "this" {
  name         = var.coder_proxy_name
  display_name = var.coder_proxy_display_name
  icon         = var.coder_proxy_icon
}

locals {
  coder = {
    CODER_ACCESS_URL          = var.coder_proxy_url
    CODER_WILDCARD_ACCESS_URL = var.coder_proxy_wildcard_url
    CODER_PRIMARY_ACCESS_URL  = var.coder_access_url
    CODER_PROXY_SESSION_TOKEN = coderd_workspace_proxy.this.session_token
    CODER_TRACE_LOGS                  = true
    CODER_LOG_FILTER                  = ".*"
  }
  secrets = {
    CODER_PROXY_SESSION_TOKEN = local.coder["CODER_PROXY_SESSION_TOKEN"]
  }
  secret_key = "key"
  secret_keys = keys(local.secrets)
  env = concat([ for k,v in merge(
    local.coder
  ) : { 
    name = k, 
    value = tostring(v)
  } if lookup(local.secrets, k, null) == null ], [
    for k,v in local.secrets : { 
      name = k, 
      valueFrom = { 
        secretKeyRef = { 
          name = replace(lower(k), "_", "-"), 
          key = local.secret_key
        } 
      } 
    } if v != null
  ])
}

resource "aws_eip" "coder" {
  count            = length(local.pub_subs)
  domain           = "vpc"
  public_ipv4_pool = "amazon"
  tags = {
    Name = "coder-eip-${count.index}"
  }
}

import {
  id = "eipalloc-011db539bef84afd0"
  to = aws_eip.coder[0]
}

resource "aws_secretsmanager_secret" "coder" {
  region = var.region
  name = "coder"
}

resource "aws_secretsmanager_secret_version" "coder" {
  region    = var.region
  secret_id = aws_secretsmanager_secret.coder.id
  secret_string = sensitive(jsonencode(local.secrets))
}

resource "kubernetes_manifest" "coder-proxy" {

  wait {
    fields = {
      "status.health.status" = "Healthy"
      "status.sync.status"   = "Synced"
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
      name        = "${var.region}.coder-proxy"
      namespace   = "argocd"
      labels      = {}
      annotations = {}
      # finalizers = [
      #   "resources-finalizer.argocd.argoproj.io"
      # ]
    }
    spec = {
      project = "default"
      source = {
        repoURL        = "https://github.com/coder/ai.coder.com"
        path           = "charts/coder-proxy"
        targetRevision = "main"
        helm = {
          releaseName = "coder-proxy"
          values = yamlencode({
            coder = {
              coder = {
                image = {
                  repo        = "ghcr.io/coder/coder"
                  tag         = "v2.35.1"
                  pullPolicy  = "IfNotPresent"
                  pullSecrets = []
                }
                workspaceProxy = true
                env = concat([for k, v in local.coder : {
                  name  = k,
                  value = tostring(v)
                  } if lookup(local.secrets, k, null) == null], [
                  for k, v in local.secrets : {
                    name = k,
                    valueFrom = {
                      secretKeyRef = {
                        name = "coder-proxy.coder",
                        key  = k
                      }
                    }
                  } if v != null
                ])
                annotations = {
                  "prometheus.io/scrape" = "true"
                  "prometheus.io/port"   = "2112"
                }
                podAnnotations = {
                  "prometheus.io/scrape" = "true"
                  "prometheus.io/port"   = "2112"
                  "checksum/config" = sha256(join(",", [
                    jsonencode(local.coder),
                    jsonencode(sensitive(local.secrets))
                  ]))
                }
                service = {
                  enable = false
                }
                tls = {
                  secretNames = [local.ssl_vol_friendly_name]
                }
                replicaCount = 2
                resources = {
                  requests = {
                    cpu    = "500m"
                    memory = "2Gi"
                  }
                  limits = {
                    cpu    = "2"
                    memory = "2Gi"
                  }
                }
                serviceAccount = {
                  name = "coder-proxy"
                  annotations = {}
                }
                nodeSelector = {}
                tolerations = [{
                  key      = "CriticalAddonsOnly"
                  operator = "Exists"
                }]
                topologySpreadConstraints = []
                affinity = {
                  nodeAffinity = {
                    requiredDuringSchedulingIgnoredDuringExecution = {
                      nodeSelectorTerms = [{
                        matchExpressions = [{
                          key      = "topology.kubernetes.io/zone"
                          operator = "In"
                          values   = [for az in local.azs : "${data.aws_region.this.region}${az}"]
                        }]
                      }]
                    }
                  }
                }
                terminationGracePeriodSeconds = 600
              }
            }
            extra = {
              service = {
                enable            = true
                loadBalancerClass = "service.k8s.aws/nlb"
                annotations = {
                  "service.beta.kubernetes.io/aws-load-balancer-nlb-target-type" = "ip"
                  "service.beta.kubernetes.io/aws-load-balancer-scheme"          = "internet-facing"
                  "service.beta.kubernetes.io/aws-load-balancer-attributes"      = "deletion_protection.enabled=false"
                  "service.beta.kubernetes.io/aws-load-balancer-eip-allocations" = join(",", aws_eip.coder[*].allocation_id)
                  "service.beta.kubernetes.io/aws-load-balancer-subnets"         = join(",", local.pub_subs)
                }
              }
              prometheus = {
                enable = true
              }
              certificate = {
                enable     = true
                name       = local.ssl_vol_friendly_name
                commonName = local.common_name
                dnsNames = [
                  local.common_name,
                  local.wildcard_name
                ]
                duration    = "2160h" # 90 days
                renewBefore = "360h"  # 15 days
                issuerRef = {
                  kind = "ClusterIssuer"
                  name = "issuer"
                }
              }
              secretStore = {
                aws = {
                  region = var.region
                }
              }
              secrets = {
                refreshInterval = "1h0m0s"
                refreshPolicy = "Periodic"
                secretArn = aws_secretsmanager_secret.coder.arn
              }
            }
          })
        }
      }
      destination = {
        server    = data.aws_eks_cluster.this.arn
        namespace = "coder-proxy"
      }
      syncPolicy = {
        syncOptions = [
          "CreateNamespace=true",
          "Delete=false"
        ]
      }
    }
  }
}