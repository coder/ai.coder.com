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

module "default-ws" {

  source = "../../../../../modules/k8s/bootstrap/coder-provisioner"

  release_name              = local.release_name
  chart_version             = var.addon_version
  chart_name                = local.chart_name
  cluster_name              = data.aws_eks_cluster.this.id
  cluster_oidc_provider_arn = data.aws_iam_openid_connect_provider.this.arn

  namespace = "coder-ws"

  coder = {
    access_url = var.coder_access_url
    org_name   = "coder"
    image_repo = var.image_repo
    image_tag  = var.image_tag
    rep_cnt    = 1
    ws_extra_rules = [{
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
      ]
    }]
    env_vars = {
      CODER_PROMETHEUS_ENABLE              = "true"
      CODER_PROMETHEUS_COLLECT_AGENT_STATS = "true"
      CODER_PROMETHEUS_COLLECT_DB_METRICS  = "true"
      # TF_VAR_namespace = "coder-ws"
    }
  }

  svc_acc = {
    create = true
    name   = "coder"
  }

  node_selector   = local.node_selector
  tolerations     = local.tolerations
  topology_spread = local.topology_spread
  affinity        = local.affinity
}

module "experiment-ws" {

  source = "../../../../../modules/k8s/bootstrap/coder-provisioner"

  release_name              = local.release_name
  chart_version             = var.addon_version
  chart_name                = local.chart_name
  cluster_name              = var.cluster_name
  cluster_oidc_provider_arn = data.aws_iam_openid_connect_provider.this.arn

  namespace = "coder-ws-experiment"

  coder = {
    access_url = var.coder_access_url
    org_name   = "experiment"
    image_repo = var.image_repo
    image_tag  = var.image_tag
    rep_cnt    = 1
    ws_extra_rules = [{
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
      ]
    },{
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
      ]
    },{
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
      ]
    }]
    env_vars = {
      CODER_PROMETHEUS_ENABLE              = "true"
      CODER_PROMETHEUS_COLLECT_AGENT_STATS = "true"
      CODER_PROMETHEUS_COLLECT_DB_METRICS  = "true"
      # TF_VAR_namespace = "coder-ws-experiment"
    }
  }

  svc_acc = {
    create = true
    name   = "coder"
  }

  node_selector   = local.node_selector
  tolerations     = local.tolerations
  topology_spread = local.topology_spread
  affinity        = local.affinity
}

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
  source      = "../../../../../modules/security/policy"
  name        = "demo-ws-eks-policy"
  path        = "/"
  description = "Coder External Demo-Provisioner Policy (EKS)"
  policy_json = data.aws_iam_policy_document.eks.json
}

module "demo-ws" {

  source = "../../../../../modules/k8s/bootstrap/coder-provisioner"

  release_name              = local.release_name
  chart_version             = var.addon_version
  chart_name                = local.chart_name
  cluster_name              = var.cluster_name
  cluster_oidc_provider_arn = data.aws_iam_openid_connect_provider.this.arn

  namespace = "coder-ws-demo"

  coder = {
    access_url = var.coder_access_url
    org_name   = "demo"
    image_repo = var.image_repo
    image_tag  = var.image_tag
    rep_cnt    = 1
    ws_extra_rules = [{
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
      ]
    },{
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
      ]
    },{
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
      ]
    }]
    env_vars = {
      CODER_PROMETHEUS_ENABLE              = "true"
      CODER_PROMETHEUS_COLLECT_AGENT_STATS = "true"
      CODER_PROMETHEUS_COLLECT_DB_METRICS  = "true"
      # TF_VAR_namespace = "coder-ws-experiment"
    }
  }

  svc_acc = {
    create = true
    name   = "coder"
    iam_policy_arns = {
      "EKSAdminPolicy" = module.eks-admin-policy.policy_arn
    }
  }

  node_selector   = local.node_selector
  tolerations     = local.tolerations
  topology_spread = local.topology_spread
  affinity        = local.affinity
}

# resource "kubernetes_cluster_role_v1" "coder-ws-demo" {
#   metadata {
#     name = "coder-ws-demo"
#   }

#   rule {
#     api_groups = ["rbac.authorization.k8s.io"]
#     resources = ["clusterrolebindings"]
#     verbs = [
#       "create",
#       "delete",
#       "deletecollection",
#       "get",
#       "list",
#       "patch",
#       "update",
#       "watch"
#     ]
#   }
# }

# resource "kubernetes_cluster_role_binding_v1" "coder-cluster-workspace-perms" {

#   depends_on = [module.demo-ws]

#   metadata {
#     name = "coder-cluster-workspace-perms"
#   }

#   subject {
#     kind = "ServiceAccount"
#     name = "coder"
#     namespace = "coder-ws-demo"
#   }

#   role_ref {
#     api_group = "rbac.authorization.k8s.io"
#     kind = "ClusterRole"
#     name = kubernetes_cluster_role_v1.coder-ws-demo.metadata[0].name
#   }
# }

module "coder-logstream-kube" {
  
  source = "../../../../../modules/k8s/bootstrap/coder-logstream"

  release_name              = "coder-logstream-kube"
  chart_version             = "0.0.15"
  chart_name                = "coder-logstream-kube"

  namespace = "coder-logstream-kube"
  image_tag = "v0.0.15"

  coder = {
    access_url = var.coder_access_url
    ws_ns      = ["coder-ws", "coder-ws-demo", "coder-ws-experiment"]
  }

  tolerations = [{
    key      = "CriticalAddonsOnly"
    operator = "Exists"
    }, {
    key    = "dedicated"
    value  = "general"
    effect = "NoSchedule"
  }]
  affinity        = {
    nodeAffinity = {
      requiredDuringSchedulingIgnoredDuringExecution = {
        nodeSelectorTerms = [{
          matchExpressions = [
            {
              key      = "eks.amazonaws.com/compute-type",
              operator = "In",
              values   = ["auto"]
            }
          ]
        }]
      }
    }
  }

}