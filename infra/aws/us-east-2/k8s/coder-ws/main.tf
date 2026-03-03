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

data "aws_caller_identity" "this" {}

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
  topology_spread = [{
    max_skew           = 2
    topology_key       = "kubernetes.io/hostname"
    when_unsatisfiable = "ScheduleAnyway"
    label_selector = {
      match_labels = {
        "app.kubernetes.io/name"    = local.chart_name
        "app.kubernetes.io/part-of" = local.chart_name
      }
    }
    match_label_keys = [
      "app.kubernetes.io/instance"
    ]
  }]
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
    podAntiAffinity = {
      preferredDuringSchedulingIgnoredDuringExecution = [{
        weight = 100
        podAffinityTerm = {
          labelSelector = {
            match_labels = {
              "app.kubernetes.io/name"    = local.chart_name
              "app.kubernetes.io/part-of" = local.chart_name
            }
          }
          topologyKey = "kubernetes.io/hostname"
        }
      }]
    }
  }

  reg_mirror = "${data.aws_caller_identity.this.account_id}.dkr.ecr.${var.region}.amazonaws.com"
  reg_suffix = {
    "ghcr" = "ghc.io"
    "k8s" = "registry.k8s.io"
    "quay" = "quay.io"
    "docker-hub" = "index.docker.io"
    "ecr-public" = "public.ecr.aws"
  }
}

resource "kubernetes_manifest" "mutate_img_policy" {
  manifest = {
    apiVersion = "policies.kyverno.io/v1"
    kind       = "MutatingPolicy"
    metadata = {
      name      = "mutate-ws-image"
    }
    spec = {
      matchConstraints = {
        matchPolicy = "Equivalent"
        namespaceSelector = {
          matchExpressions = [{
            key = "kubernetes.io/metadata.name"
            operator = "In"
            values = [
              "default", 
              "litellm", 
              "observability",
              "ebs-controller",
              "coder-ws-experiment",
              "coder-ws"
            ]
          }]
        }
        objectSelector = {
          matchExpressions = [
            {
              key = "app.kubernetes.io/name"
              operator = "NotIn"
              values = [
                # "coder-provisioner", 
                "coder"
              ]
            },
            {
              key = "app.kubernetes.io/managed-by"
              operator = "NotIn"
              values = [
                # "Helm",
                "test"
              ]
            }
          ]
        }
        resourceRules = [
          {
            apiGroups   = [""]
            apiVersions = ["v1"]
            operations  = ["CREATE", "UPDATE"]
            resources   = ["pods"]
          }
        ]
      }
      mutations = [ for k in ["containers", "initContainers", "ephemeralContainers"] : {
        patchType = "JSONPatch"
        jsonPatch = {
          expression = <<-EOT
            object.spec.?${k}.orValue([]).map(c, 
              %{ for suffix,reg in local.reg_suffix ~}
              image(c.image).registry() == "${reg}" ? 
              JSONPatch{
                op: "replace",
                path: "/spec/${k}/" + string(object.spec.?${k}.orValue([]).indexOf(c)) + "/image",
                value: "${local.reg_mirror}" + "/" + "${suffix}" + "/" + string(image(c.image).repository()) + ":" + string(image(c.image).tag())
              } :
              %{ endfor ~}
              null
            ).filter(p, p != null)
          EOT
        }
      } ]
    }
  }
}

module "default-ws" {

  depends_on = [ kubernetes_manifest.mutate_img_policy ]
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
    rep_cnt    = 4
    env_vars = {
      CODER_PROMETHEUS_ENABLE              = "true"
      CODER_PROMETHEUS_COLLECT_AGENT_STATS = "true"
      CODER_PROMETHEUS_COLLECT_DB_METRICS  = "true"
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

  depends_on = [ kubernetes_manifest.mutate_img_policy ]
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
    rep_cnt    = 4
    env_vars = {
      CODER_PROMETHEUS_ENABLE              = "true"
      CODER_PROMETHEUS_COLLECT_AGENT_STATS = "true"
      CODER_PROMETHEUS_COLLECT_DB_METRICS  = "true"
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

module "demo-ws" {

  depends_on = [ kubernetes_manifest.mutate_img_policy ]
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
    rep_cnt    = 4
    env_vars = {
      CODER_PROMETHEUS_ENABLE              = "true"
      CODER_PROMETHEUS_COLLECT_AGENT_STATS = "true"
      CODER_PROMETHEUS_COLLECT_DB_METRICS  = "true"
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

module "coder-logstream-kube" {
  
  source = "../../../../../modules/k8s/bootstrap/coder-logstream"

  release_name              = "coder-logstream-kube"
  chart_version             = "0.0.14"
  chart_name                = "coder-logstream-kube"

  namespace = "coder-logstream-kube"

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