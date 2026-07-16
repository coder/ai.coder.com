provider "aws" {
  region  = var.region
  profile = var.profile
}

data "aws_region" "this" {}

data "aws_caller_identity" "this" {}

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
  db_instance_identifier = var.coder_db_rds_name
}

data "aws_vpc" "this" {
  tags = {
    Name = var.vpc_name
  }
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.this.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.this.token
}

locals {
  region       = data.aws_region.this.region
  account_id   = data.aws_caller_identity.this.account_id
  azs          = var.azs
  pub_subs     = [for az in local.azs : "${var.vpc_name}-public-${local.region}${az}"]
  release_name = "coder"
  rds_db_name  = split(".", data.aws_db_instance.coder.endpoint)[0]

  common_name           = trimprefix(trimprefix(var.coder_access_url, "https://"), "http://")
  wildcard_name         = trimprefix(trimprefix(var.coder_wildcard_access_url, "https://"), "http://")
  ssl_vol_friendly_name = replace(local.common_name, ".", "-")
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
  id = "eipalloc-0d77e626a86e01d9b"
  to = aws_eip.coder[0]
}

import {
  id = "eipalloc-00b0abb2240ba8036"
  to = aws_eip.coder[1]
}

import {
  id = "eipalloc-0b14ee1e7717ea68d"
  to = aws_eip.coder[2]
}

data "aws_iam_policy_document" "rds" {
  statement {
    effect  = "Allow"
    actions = ["rds-db:connect"]
    resources = [
      "arn:aws:rds-db:${local.region}:${local.account_id}:dbuser:${data.aws_db_instance.coder.resource_id}/${var.coder_db_username}"
    ]
  }
}

module "rds-policy" {
  source      = "../../../../../../modules/security/policy"
  name        = "coder-srv-${local.rds_db_name}"
  path        = "/${var.cluster_name}/${local.region}/"
  description = "Coder DB IAM Access Policy"
  policy_json = data.aws_iam_policy_document.rds.json
}

data "aws_iam_policy_document" "assume-role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    resources = [
      "arn:aws:iam::${data.aws_caller_identity.this.account_id}:role/coder-gateway-*"
    ]
  }
}

module "assume-role-policy" {
  source      = "../../../../../../modules/security/policy"
  name        = "coder-srv-assume-select"
  path        = "/${var.cluster_name}/${local.region}/"
  description = "Coder STS Assume Role Policy"
  policy_json = data.aws_iam_policy_document.assume-role.json
}

module "provisioner-oidc-role" {
  source       = "../../../../../../modules/security/role/access-entry"
  name         = "coder-srv"
  path         = "/${var.cluster_name}/${local.region}/"
  cluster_name = var.cluster_name
  policy_arns = {
    "CoderRDSDBPolicy"      = module.rds-policy.policy_arn
    "CoderAssumeRolePolicy" = module.assume-role-policy.policy_arn
  }
  cluster_policy_arns = {}
  oidc_principals = {
    "${data.aws_iam_openid_connect_provider.this.arn}" = ["system:serviceaccount:*:*"]
  }
}

locals {
  coder = {
    CODER_ACCESS_URL          = var.coder_access_url
    CODER_WILDCARD_ACCESS_URL = var.coder_wildcard_access_url

    # TLS Termination handled on the LB
    CODER_REDIRECT_TO_ACCESS_URL = "true"
    CODER_TLS_ENABLE             = "true"

    CODER_ENABLE_TERRAFORM_DEBUG_MODE = "true"
    CODER_TRACE_LOGS                  = "true"
    CODER_TRACE_ENABLE                = "true"
    CODER_LOG_FILTER                  = ".*"
    CODER_SWAGGER_ENABLE              = "true"
    CODER_UPDATE_CHECK                = "true"
    CODER_CLI_UPGRADE_MESSAGE         = "true"

    CODER_PROVISIONER_DAEMONS               = "0"
    CODER_PROVISIONER_FORCE_CANCEL_INTERVAL = "10m0s"
    CODER_QUIET_HOURS_DEFAULT_SCHEDULE      = "CRON_TZ=America/Los_Angeles 50 23 * * *"
    CODER_ALLOW_CUSTOM_QUIET_HOURS          = "false"
    CODER_EXPERIMENTS                       = join(",", [])

    CODER_PROMETHEUS_ENABLE              = "true"
    CODER_PROMETHEUS_COLLECT_AGENT_STATS = "true"
    CODER_PROMETHEUS_COLLECT_DB_METRICS  = "true"

    CODER_PG_AUTH           = "awsiamrds"
    CODER_PG_CONNECTION_URL = "postgresql://${var.coder_db_username}@${data.aws_db_instance.coder.endpoint}/${var.coder_db_name}"

    CODER_OIDC_ISSUER_URL    = var.coder_oidc_secret_issuer_url
    CODER_OIDC_CLIENT_ID     = var.coder_oidc_secret_client_id
    CODER_OIDC_CLIENT_SECRET = var.coder_oidc_secret_client_secret
    CODER_OIDC_SIGN_IN_TEXT  = "Welcome to Coder's AI Environment!"
    CODER_OIDC_ICON_URL      = var.oidc_icon_url
    CODER_OIDC_SCOPES        = join(",", var.oidc_scopes)
    CODER_OIDC_EMAIL_DOMAIN  = var.oidc_email_domain

    CODER_AIBRIDGE_ENABLED            = "true"
    CODER_AIBRIDGE_STRUCTURED_LOGGING = "true"

    CODER_EXTERNAL_AUTH_0_ID            = "primary-github"
    CODER_EXTERNAL_AUTH_0_TYPE          = "github"
    CODER_EXTERNAL_AUTH_0_CLIENT_ID     = var.coder_github_external_auth_secret_client_id
    CODER_EXTERNAL_AUTH_0_CLIENT_SECRET = var.coder_github_external_auth_secret_client_secret

    CODER_OAUTH2_GITHUB_DEFAULT_PROVIDER_ENABLE = "false"
    CODER_OAUTH2_GITHUB_CLIENT_ID               = var.coder_oauth_secret_client_id
    CODER_OAUTH2_GITHUB_CLIENT_SECRET           = var.coder_oidc_secret_client_secret
    CODER_OAUTH2_GITHUB_ALLOW_SIGNUPS           = "false"
    CODER_OAUTH2_GITHUB_DEVICE_FLOW             = "false"
    CODER_OAUTH2_GITHUB_ALLOW_EVERYONE          = "false"
    CODER_OAUTH2_GITHUB_ALLOWED_ORGS            = join(",", var.coder_github_allowed_orgs)
  }
  secrets = merge({
    CODER_OAUTH2_GITHUB_CLIENT_SECRET   = local.coder["CODER_OAUTH2_GITHUB_CLIENT_SECRET"]
    CODER_OIDC_CLIENT_SECRET            = local.coder["CODER_OIDC_CLIENT_SECRET"]
    CODER_PG_CONNECTION_URL             = local.coder["CODER_PG_CONNECTION_URL"]
    CODER_EXTERNAL_AUTH_0_CLIENT_SECRET = local.coder["CODER_EXTERNAL_AUTH_0_CLIENT_SECRET"]
  })
}

resource "kubernetes_namespace_v1" "coder" {
  depends_on = [ aws_eip.coder ]
  metadata {
    name = "coder"
  }
}

import {
  id = "coder"
  to = kubernetes_namespace_v1.coder
}

resource "kubernetes_manifest" "coder" {

  wait {
    fields = {
      "status.health.status" = "Healthy"
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
      name        = local.release_name
      namespace   = "argocd"
      labels      = {}
      annotations = {}
    }
    spec = {
      project = "default"
      source = {
        repoURL        = "https://github.com/coder/ai.coder.com"
        path          = "infra/aws/us-east-2/k8s/argo/coder-server/charts/coder"
        targetRevision = "main"
        helm = {
          values = yamlencode({
            coder = {
              coder = {
                image = {
                  repo        = "ghcr.io/coder/coder"
                  tag         = var.addon_version
                  pullPolicy  = "IfNotPresent"
                  pullSecrets = []
                }
                env = concat([for k, v in merge(
                  local.coder,
                  ) : {
                  name  = k,
                  value = tostring(v)
                  } if lookup(local.secrets, k, null) == null], [
                  for k, v in local.secrets : {
                    name = k,
                    valueFrom = {
                      secretKeyRef = {
                        name = replace(lower(k), "_", "-"),
                        key  = "key"
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
                }
                service = {
                  enable = false
                }
                tls = {
                  secretNames = [local.ssl_vol_friendly_name]
                }
                replicaCount = 0
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
                  name = local.release_name
                  annotations = {
                    "eks.amazonaws.com/role-arn" : module.provisioner-oidc-role.role_arn
                  }
                }
                nodeSelector = {}
                tolerations = [{
                  key    = "platform"
                  value  = "coder-server"
                  effect = "NoSchedule"
                }]
                topologySpreadConstraints = []
                affinity = {
                  nodeAffinity = {
                    requiredDuringSchedulingIgnoredDuringExecution = {
                      nodeSelectorTerms = [{
                        matchExpressions = [
                          {
                            key      = "topology.kubernetes.io/zone"
                            operator = "In"
                            values   = [for az in local.azs : "${data.aws_region.this.region}${az}"]
                          },
                          {
                            key      = "node.coder.io/used-for",
                            operator = "In",
                            values   = ["coder-server"]
                          }
                        ]
                      }]
                    }
                  }
                  podAntiAffinity = {
                    preferredDuringSchedulingIgnoredDuringExecution = []
                    requiredDuringSchedulingIgnoredDuringExecution  = []
                  }
                }
                terminationGracePeriodSeconds = 600
              }
            }
            extra = {
              service = {
                enable = true
                loadBalancerClass = "service.k8s.aws/nlb"
                annotations = {
                    "service.beta.kubernetes.io/aws-load-balancer-nlb-target-type" = "ip"
                    "service.beta.kubernetes.io/aws-load-balancer-scheme"          = "internet-facing"
                    "service.beta.kubernetes.io/aws-load-balancer-attributes"      = "deletion_protection.enabled=false,load_balancing.cross_zone.enabled=true"
                    "service.beta.kubernetes.io/aws-load-balancer-eip-allocations" = join(",", aws_eip.coder[*].allocation_id)
                    "service.beta.kubernetes.io/aws-load-balancer-subnets"         = join(",", local.pub_subs)
                  }
              }
              prometheus = {
                enable = true
              }
              certificate = {
                enable = true
                name = local.ssl_vol_friendly_name
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
            }
          })
        }
      }
      destination = {
        server    = data.aws_eks_cluster.this.arn
        namespace = kubernetes_namespace_v1.coder.metadata[0].name
      }
      syncPolicy = {
        syncOptions = [
          "CreateNamespace=false",
          "Delete=false",
          "ServerSideApply=true"
        ]
      }
    }
  }
}

resource "kubernetes_secret_v1" "coder" {

  for_each = toset(keys(local.secrets))

  metadata {
    name = replace(lower(each.key), "_", "-")
    namespace = kubernetes_namespace_v1.coder.metadata[0].name
    annotations = {
      "custom.kubernetes.secret/key" = "key"
    }
  }
  type = "Opaque"
  data = {
    "key" = sensitive(base64encode(local.secrets[each.key]))
  }
}

import {
  id = "coder/coder-external-auth-0-client-secret"
  to = kubernetes_secret_v1.coder["CODER_EXTERNAL_AUTH_0_CLIENT_SECRET"]
}

import {
  id = "coder/coder-oauth2-github-client-secret"
  to = kubernetes_secret_v1.coder["CODER_OAUTH2_GITHUB_CLIENT_SECRET"]
}

import {
  id = "coder/coder-oidc-client-secret"
  to = kubernetes_secret_v1.coder["CODER_OIDC_CLIENT_SECRET"]
}

import {
  id = "coder/coder-pg-connection-url"
  to = kubernetes_secret_v1.coder["CODER_PG_CONNECTION_URL"]
}