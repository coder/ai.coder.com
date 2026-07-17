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

provider "kubernetes" {
  host                   = data.aws_eks_cluster.this.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.this.token
}

provider "coderd" {
  url   = var.coder_access_url
  token = jsondecode(data.http.login.response_body).session_token
}

locals {
  release_name = "coder"
  chart_name   = "coder-provisioner"
  namespace    = "coder"
  coder = {
    CODER_URL                            = var.coder_access_url
    CODER_PROMETHEUS_ENABLE              = "true"
    CODER_PROMETHEUS_COLLECT_AGENT_STATS = "true"
    CODER_PROMETHEUS_COLLECT_DB_METRICS  = "true"
  }
  node_selector   = {}
  topology_spread = []
  tolerations = [{
    key      = "coder"
    operator = "Exists"
  }]
  affinity = {
    nodeAffinity = {
      requiredDuringSchedulingIgnoredDuringExecution = {
        nodeSelectorTerms = [{
          matchExpressions = [
            {
              key      = "node.coder.io/used-for",
              operator = "In",
              values   = ["coder-provisioner"]
            }
          ]
        }]
      }
    }
    podAntiAffinity = {}
  }
}

module "eks-admin-policy" {
  source      = "../../../../../../modules/security/policy"
  name        = "demo-ws-eks-policy"
  path        = "/"
  description = "Coder External Demo-Provisioner Policy (EKS)"
  policy_json = data.aws_iam_policy_document.eks.json
}

module "iam-policy" {
  source      = "../../../../../../modules/security/policy"
  name        = "Provisioner-${data.aws_region.this.region}"
  path        = "/"
  description = "Coder External Provisioner Policy"
  policy_json = data.aws_iam_policy_document.ext-prov.json
}

module "oidc-role" {
  source       = "../../../../../../modules/security/role/access-entry"
  name         = "provisioner-${data.aws_region.this.region}"
  cluster_name = var.cluster_name
  policy_arns = {
    "AmazonEC2ReadOnlyAccess" = "arn:aws:iam::aws:policy/AmazonEC2ReadOnlyAccess"
    "TFProvisionerPolicy"     = module.iam-policy.policy_arn
  }
  cluster_policy_arns = {}
  oidc_principals = {
    "${data.aws_iam_openid_connect_provider.this.arn}" = ["system:serviceaccount:*:*"]
  }
  tags = {}
}

locals {
  coder-ws = {
    "coder-ws" = {
      org_name  = "coder"
      namespace = "coder-ws"
    },
    "coder-ws-experiment" = {
      org_name  = "experiment"
      namespace = "coder-ws-experiment"
    },
    "coder-ws-demo" = {
      org_name  = "demo"
      namespace = "coder-ws-demo"
    }
  }
}

data "coderd_organization" "coder" {
  for_each = local.coder-ws
  name     = each.value.org_name
}

module "coder-provisioner" {

  for_each = local.coder-ws

  source           = "../../../../../../modules/coder/provisioner"
  organization_id  = data.coderd_organization.coder[each.key].id
  provisioner_tags = {}
}

# Avoide ApplicationSets as a K8s Manifest: 
# - https://github.com/hashicorp/terraform-provider-kubernetes/pull/2800
# - https://github.com/hashicorp/terraform-provider-kubernetes/issues/2757

resource "kubernetes_manifest" "coder-provisioner" {

  for_each = local.coder-ws

  wait {
    fields = {
      "status.health.status" = "Healthy"
      "status.sync.status"   = "Synced"
    }
  }

  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name        = "${var.region}.${each.key}"
      namespace   = "argocd"
      labels      = {}
      annotations = {}
    }
    spec = {
      project = "default"
      source = {
        repoURL        = "https://github.com/coder/ai.coder.com"
        path           = "charts/coder-provisioner"
        targetRevision = "main"
        helm = {
          releaseName = each.key
          values = yamlencode({
            coder = {
              image = {
                repo        = "ghcr.io/coder/coder"
                tag         = var.addon_version
                pullPolicy  = "IfNotPresent"
                pullSecrets = []
              }
              serviceAccount = {
                workspacePerms    = true
                enableDeployments = true
                name              = "coder"
                disableCreate     = false
                extraRules = [{
                  apiGroups = [""]
                  resources = ["configmaps"]
                  verbs = [
                    "create",
                    "delete",
                    "deletecollection",
                    "get",
                    "list",
                    "patch",
                    "update",
                    "watch"
                  ] }, {
                  apiGroups = [""]
                  resources = ["serviceaccounts"]
                  verbs = [
                    "create",
                    "delete",
                    "deletecollection",
                    "get",
                    "list",
                    "patch",
                    "update",
                    "watch"
                  ] }, {
                  apiGroups = ["rbac.authorization.k8s.io"]
                  resources = ["clusterrolebindings"]
                  verbs = [
                    "create",
                    "delete",
                    "deletecollection",
                    "get",
                    "list",
                    "patch",
                    "update",
                    "watch"
                ] }]
                annotations = {
                  "eks.amazonaws.com/role-arn" = module.oidc-role.role_arn
                }
              }
              podAnnotations = {
                "prometheus.io/scrape" = "true"
                "prometheus.io/port"   = "2112"
                "checksum/config" = sha256(join(",", [
                  jsonencode(local.coder),
                  jsonencode(sensitive(module.coder-provisioner[each.key].provisioner_key_secret)),
                  jsonencode(module.oidc-role.role_arn)
                ]))
              }
              env = [
                for k, v in local.coder : { name = k, value = v }
              ]
              volumeClaimTemplates = [{
                metadata = {
                  name = "cache"
                }
                spec = {
                  accessModes      = ["ReadWriteOnce"]
                  storageClassName = "gp3-automode"
                  resources = {
                    requests = {
                      storage = "10Gi"
                    }
                  }
                }
              }]
              volumeMounts = [{
                mountPath = "/home/coder/.cache/coder"
                name      = "cache"
              }]
              podSecurityContext = {
                fsGroup = 1000
              }
              securityContext = {
                runAsNonRoot             = true
                runAsUser                = 1000
                runAsGroup               = 1000
                readOnlyRootFilesystem   = false
                allowPrivilegeEscalation = false
                seccompProfile = {
                  type = "RuntimeDefault"
                }
              }
              resources = {
                requests = {
                  cpu    = "1"
                  memory = "1Gi"
                }
                limits = {
                  cpu    = "1"
                  memory = "1Gi"
                }
              }
              nodeSelector              = local.node_selector
              replicaCount              = 1
              affinity                  = local.affinity
              tolerations               = local.tolerations
              topologySpreadConstraints = local.topology_spread
            }
            provisionerDaemon = {
              keySecretKey                  = "key"
              keySecretName                 = kubernetes_secret_v1.coder-provisioner-key[each.key].metadata[0].name
              terminationGracePeriodSeconds = 600
            }
            extraTemplates = []
          })
        }
      }
      destination = {
        server    = data.aws_eks_cluster.this.arn
        namespace = each.value.namespace
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

resource "kubernetes_secret_v1" "coder-provisioner-key" {
  for_each = local.coder-ws
  metadata {
    name      = "coder-provisioner-key"
    namespace = each.value.namespace
  }
  data = {
    key = sensitive(module.coder-provisioner[each.key].provisioner_key_secret)
  }
}

resource "kubernetes_manifest" "coder-logstream-kube" {

  depends_on = [kubernetes_manifest.coder-provisioner]

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
      name        = "${var.region}.coder-logstream-kube"
      namespace   = "argocd"
      labels      = {}
      annotations = {}
    }
    spec = {
      project = "default"
      source = {
        repoURL        = "https://helm.coder.com/logstream-kube"
        chart          = "coder-logstream-kube"
        targetRevision = "0.0.15"
        helm = {
          releaseName = "coder-logstream-kube"
          values = yamlencode({
            url        = var.coder_access_url
            namespaces = [for i in values(local.coder-ws) : i.namespace]
            image = {
              repo       = "ghcr.io/coder/coder-logstream-kube"
              tag        = "v0.0.15"
              pullPolicy = "IfNotPresent"
            }
            nodeSelector   = local.node_selector
            affinity       = local.affinity
            tolerations    = local.tolerations
            topologySpread = local.topology_spread
          })
        }
      }
      destination = {
        server    = data.aws_eks_cluster.this.arn
        namespace = "coder-logstream-kube"
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