provider "aws" {
  region  = var.region
  profile = var.profile
}

data "aws_region" "this" {}

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

provider "helm" {
  kubernetes = {
    host                   = data.aws_eks_cluster.this.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)
    token                  = data.aws_eks_cluster_auth.this.token
  }
}

provider "argocd" {
  kubernetes {
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

provider "coderd" {
  url   = var.coder_access_url
  token = jsondecode(data.http.login.response_body).session_token
}

locals {
  release_name = "coder"
  chart_name   = "coder-provisioner"
  namespace    = "coder"

  node_selector = {}
  topology_spread = []
  # topology_spread = [{
  #   max_skew           = 2
  #   topology_key       = "kubernetes.io/hostname"
  #   when_unsatisfiable = "ScheduleAnyway"
  #   label_selector = {
  #     match_labels = {
  #       "app.kubernetes.io/name"    = local.chart_name
  #       "app.kubernetes.io/part-of" = local.chart_name
  #     }
  #   }
  #   match_label_keys = [
  #     "app.kubernetes.io/instance"
  #   ]
  # }]
  tolerations = [{
    key      = "coder"
    operator = "Exists"
    values   = ["provisioner"]
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
    # podAntiAffinity = {
    #   preferredDuringSchedulingIgnoredDuringExecution = [{
    #     weight = 100
    #     podAffinityTerm = {
    #       labelSelector = {
    #         match_labels = {
    #           "app.kubernetes.io/name"    = local.chart_name
    #           "app.kubernetes.io/part-of" = local.chart_name
    #         }
    #       }
    #       topologyKey = "kubernetes.io/hostname"
    #     }
    #   }]
    # }
  }
}

# module "default-ws" {

#   source = "../../../../../modules/k8s/bootstrap/coder-provisioner"

#   release_name              = local.release_name
#   chart_version             = var.addon_version
#   chart_name                = local.chart_name
#   cluster_name              = data.aws_eks_cluster.this.id
#   cluster_oidc_provider_arn = data.aws_iam_openid_connect_provider.this.arn

#   namespace = "coder-ws"

#   coder = {
#     access_url = var.coder_access_url
#     org_name   = "coder"
#     image_repo = var.image_repo
#     image_tag  = var.image_tag
#     rep_cnt    = 1
#     ws_extra_rules = [{
#       apiGroups = [""]
#       resources = ["configmaps"]
#       verbs = [
#         "create",
#         "delete",
#         "deletecollection",
#         "get",
#         "list",
#         "patch",
#         "update",
#         "watch"
#       ]
#     }]
#     env_vars = {
#       CODER_PROMETHEUS_ENABLE              = "true"
#       CODER_PROMETHEUS_COLLECT_AGENT_STATS = "true"
#       CODER_PROMETHEUS_COLLECT_DB_METRICS  = "true"
#       # TF_VAR_namespace = "coder-ws"
#     }
#   }

#   svc_acc = {
#     create = true
#     name   = "coder"
#   }

#   node_selector   = local.node_selector
#   tolerations     = local.tolerations
#   topology_spread = local.topology_spread
#   affinity        = local.affinity
# }

# module "experiment-ws" {

#   source = "../../../../../modules/k8s/bootstrap/coder-provisioner"

#   release_name              = local.release_name
#   chart_version             = var.addon_version
#   chart_name                = local.chart_name
#   cluster_name              = var.cluster_name
#   cluster_oidc_provider_arn = data.aws_iam_openid_connect_provider.this.arn

#   namespace = "coder-ws-experiment"

#   coder = {
#     access_url = var.coder_access_url
#     org_name   = "experiment"
#     image_repo = var.image_repo
#     image_tag  = var.image_tag
#     rep_cnt    = 1
#     ws_extra_rules = [{
#       apiGroups = [""]
#       resources = ["configmaps"]
#       verbs = [
#         "create",
#         "delete",
#         "deletecollection",
#         "get",
#         "list",
#         "patch",
#         "update",
#         "watch"
#       ]
#     },{
#       apiGroups = [""]
#       resources = ["serviceaccounts"]
#       verbs = [
#         "create",
#         "delete",
#         "deletecollection",
#         "get",
#         "list",
#         "patch",
#         "update",
#         "watch"
#       ]
#     },{
#       apiGroups = ["rbac.authorization.k8s.io"]
#       resources = ["clusterrolebindings"]
#       verbs = [
#         "create",
#         "delete",
#         "deletecollection",
#         "get",
#         "list",
#         "patch",
#         "update",
#         "watch"
#       ]
#     }]
#     env_vars = {
#       CODER_PROMETHEUS_ENABLE              = "true"
#       CODER_PROMETHEUS_COLLECT_AGENT_STATS = "true"
#       CODER_PROMETHEUS_COLLECT_DB_METRICS  = "true"
#       # TF_VAR_namespace = "coder-ws-experiment"
#     }
#   }

#   svc_acc = {
#     create = true
#     name   = "coder"
#   }

#   node_selector   = local.node_selector
#   tolerations     = local.tolerations
#   topology_spread = local.topology_spread
#   affinity        = local.affinity
# }

data "aws_iam_policy_document" "eks" {
  statement {
    effect = "Allow"
    actions = [
      "eks:*",
      "iam:*"
    ]
    resources = ["*"]
  }
}

module "eks-admin-policy" {
  source      = "../../../../../../modules/security/policy"
  name        = "demo-ws-eks-policy"
  path        = "/"
  description = "Coder External Demo-Provisioner Policy (EKS)"
  policy_json = data.aws_iam_policy_document.eks.json
}

# module "demo-ws" {

#   source = "../../../../../modules/k8s/bootstrap/coder-provisioner"

#   release_name              = local.release_name
#   chart_version             = var.addon_version
#   chart_name                = local.chart_name
#   cluster_name              = var.cluster_name
#   cluster_oidc_provider_arn = data.aws_iam_openid_connect_provider.this.arn

#   namespace = "coder-ws-demo"

#   coder = {
#     access_url = var.coder_access_url
#     org_name   = "demo"
#     image_repo = var.image_repo
#     image_tag  = var.image_tag
#     rep_cnt    = 1
#     ws_extra_rules = [{
#       apiGroups = [""]
#       resources = ["configmaps"]
#       verbs = [
#         "create",
#         "delete",
#         "deletecollection",
#         "get",
#         "list",
#         "patch",
#         "update",
#         "watch"
#       ]
#     },{
#       apiGroups = [""]
#       resources = ["serviceaccounts"]
#       verbs = [
#         "create",
#         "delete",
#         "deletecollection",
#         "get",
#         "list",
#         "patch",
#         "update",
#         "watch"
#       ]
#     },{
#       apiGroups = ["rbac.authorization.k8s.io"]
#       resources = ["clusterrolebindings"]
#       verbs = [
#         "create",
#         "delete",
#         "deletecollection",
#         "get",
#         "list",
#         "patch",
#         "update",
#         "watch"
#       ]
#     }]
#     env_vars = {
#       CODER_PROMETHEUS_ENABLE              = "true"
#       CODER_PROMETHEUS_COLLECT_AGENT_STATS = "true"
#       CODER_PROMETHEUS_COLLECT_DB_METRICS  = "true"
#       # TF_VAR_namespace = "coder-ws-experiment"
#     }
#   }

#   svc_acc = {
#     create = true
#     name   = "coder"
#     iam_policy_arns = {
#       "EKSAdminPolicy" = module.eks-admin-policy.policy_arn
#     }
#   }

#   node_selector   = local.node_selector
#   tolerations     = local.tolerations
#   topology_spread = local.topology_spread
#   affinity        = local.affinity
# }

locals {
  # coder-provisioner-values = yamlencode({
  #   coder = {
  #     image = {
  #       repo        = var.coder.image_repo
  #       tag         = var.coder.image_tag
  #       pullPolicy  = var.coder.image_pull_policy
  #       pullSecrets = var.coder.image_pull_secrets
  #     }
  #     serviceAccount = {
  #       workspacePerms    = true
  #       enableDeployments = true
  #       name              = var.svc_acc.name
  #       disableCreate     = !var.svc_acc.create
  #       workspaceNamespaces = [ for v in var.coder.ws_ns : { name = v  } ]
  #       extraRules = var.coder.ws_extra_rules
  #       annotations = merge({
  #         "eks.amazonaws.com/role-arn" = module.oidc-role.role_arn
  #       }, var.svc_acc.annots)
  #     }
  #     podAnnotations = {
  #       "prometheus.io/scrape" = "true"
  #       "prometheus.io/port"   = "2112"
  #     }
  #     env = [
  #       for k, v in merge({
  #         CODER_URL = var.coder.access_url
  #       }, var.coder.env_vars) : { name = k, value = v }
  #     ]
  #     volumeClaimTemplates = [{
  #       metadata = {
  #         name = "cache"
  #       }
  #       spec = {
  #         accessModes = ["ReadWriteOnce"]
  #         storageClassName = "gp3-automode"
  #         resources = {
  #           requests = {
  #             storage = "10Gi"
  #           }
  #         }
  #       }
  #     }]
  #     # volumes = [{
  #     #   name = "cache"
  #     #   persistentVolumeClaim = {
  #     #     claimName = kubernetes_persistent_volume_claim_v1.cache.metadata[0].name
  #     #     readOnly = false
  #     #   }
  #     # }]
  #     volumeMounts = [{
  #       mountPath = "/home/coder/.cache/coder"
  #       name = "cache"
  #       readOnly = false
  #     }]
  #     podSecurityContext = {
  #       fsGroup = 1000
  #     }
  #     securityContext = {
  #       runAsNonRoot           = true
  #       runAsUser              = 1000
  #       runAsGroup             = 1000
  #       readOnlyRootFilesystem = null
  #       seccompProfile = {
  #         type = "RuntimeDefault"
  #       }
  #       allowPrivilegeEscalation = false
  #     }
  #     resources = {
  #       requests = var.rsrc_req
  #       limits   = var.rsrc_lim
  #     }
  #     nodeSelector              = {} # var.node_selector
  #     replicaCount              = # var.coder.rep_cnt
  #     tolerations               = # var.tolerations
  #     topologySpreadConstraints = local.topology_spread
  #     affinity = var.affinity
  #   }
  #   provisionerDaemon = {
  #     keySecretKey                  = kubernetes_secret_v1.ext-prov.metadata[0].annotations["custom.kubernetes.secret/key"]
  #     keySecretName                 = kubernetes_secret_v1.ext-prov.metadata[0].name
  #     terminationGracePeriodSeconds = 600
  #   }
  # })
}

resource "argocd_application_set" "coder-workspaces" {
  metadata {
    name = "coder-workspaces"
    namespace = "argocd"
    labels = {}
    annotations = {}
  }
  spec {
    generator {
      list {
        elements = [{
          name = "coder-ws"
          namespace = "coder-ws-test"
          repoURL = "https://github.com/coder/ai.coder.com.git"
          path = "infra/aws/us-east-2/k8s/argo/coder-ws/charts/coder-provisioner"
          chart = "coder-provisioner"
          revision = "main"
          values = yamlencode({})
          template = yamlencode({
            spec = {
              sync_policy = {
                sync_options = ["CreateNamespace=true"]
              }
            }
          })
        },{
          name = "coder-ws-experiment"
          namespace = "coder-ws-experiment-test"
          repoURL = "https://github.com/coder/ai.coder.com.git"
          path = "infra/aws/us-east-2/k8s/argo/coder-ws/charts/coder-provisioner"
          chart = "coder-provisioner"
          revision = "main"
          values = yamlencode({})
          template = yamlencode({
            spec = {
              sync_policy = {
                sync_options = ["CreateNamespace=true"]
              }
            }
          })
        },{
          name = "coder-ws-demo"
          namespace = "coder-ws-demo-test"
          repoURL = "https://github.com/coder/ai.coder.com.git"
          path = "infra/aws/us-east-2/k8s/argo/coder-ws/charts/coder-provisioner"
          chart = "coder-provisioner"
          revision = "main"
          values = yamlencode({})
          template = yamlencode({
            spec = {
              sync_policy = {
                sync_options = ["CreateNamespace=true"]
              }
            }
          })
        },{
          name = "coder-logstream-kube"
          namespace = "coder-logstream-kube-test"
          repoURL = "https://github.com/coder/ai.coder.com.git"
          path = "infra/aws/us-east-2/k8s/argo/coder-ws/charts/coder-provisioner"
          chart = "coder-logstream-kube"
          revision = "main"
          values = yamlencode({
            url = var.coder_access_url
            namespaces = ["coder-ws", "coder-ws-demo", "coder-ws-experiment"]
            image = {
              repo = "ghcr.io/coder/coder-logstream-kube"
              tag = "v0.0.15"
              pullPolicy = "IfNotPresent"
            }
            
            nodeSelector = {} # var.node_selector
            affinity = {} # var.affinity
            tolerations = {} # var.tolerations
          })
          template = yamlencode({
            spec = {
              sync_policy = {
                sync_options = ["CreateNamespace=true"]
              }
            }
          })
        }]
      }
    }

    template {
      metadata {
        name = "{{name}}"
      }
      spec {
        source {
          repo_url        = "{{repoURL}}"
          path            = "{{path}}"
          target_revision = "{{version}}"
        }
        # repo_url = "{{repoURL}}"
        # chart = "{{chart}}"
        # target_revision = "{{version}}"
        destination {
          server = "https://kubernetes.default.svc"
          namespace = "{{namespace}}"
        }
      }
    }
  }
}