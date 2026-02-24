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
    attempts = 5
    min_delay_ms = (5*1000) # 5 seconds 
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
  node_selector = {}
  tolerations = [{
    key = "CriticalAddonsOnly"
    operator = "Exists"
  }]
  affinity = {
    nodeAffinity = {
      requiredDuringSchedulingIgnoredDuringExecution = {
        nodeSelectorTerms = [{
          matchExpressions = [{
            key = "eks.amazonaws.com/compute-type"
            operator = "In"
            values = ["auto"]
          }]
        }]
      }
    }
  }
  release_name = "coder"
  chart_name = "coder-provisioner"
  namespace = "coder"
}

module "default-ws" {

  source                    = "../../../../../modules/k8s/bootstrap/coder-provisioner"

  release_name              = local.release_name
  chart_version             = var.addon_version
  chart_name                = local.chart_name
  cluster_name              = data.aws_eks_cluster.this.id
  cluster_oidc_provider_arn = data.aws_iam_openid_connect_provider.this.arn

  namespace = "coder-ws"

  coder = {
    access_url = var.coder_access_url
    org_name = "coder"
    image_repo                       = var.image_repo
    image_tag                        = var.image_tag
    rep_cnt = 4
    env_vars = {
      CODER_PROMETHEUS_ENABLE              = "true"
      CODER_PROMETHEUS_COLLECT_AGENT_STATS = "true"
      CODER_PROMETHEUS_COLLECT_DB_METRICS  = "true"
    }
  }

  svc_acc = {
    create = true
    name = "coder"
  }

  node_selector = local.node_selector
  tolerations   = local.tolerations
  affinity = local.affinity
}

module "experiment-ws" {

  source = "../../../../../modules/k8s/bootstrap/coder-provisioner"

  release_name              = local.release_name
  chart_version             = var.addon_version
  chart_name                = local.chart_name
  cluster_name              = var.cluster_name
  cluster_oidc_provider_arn = data.aws_iam_openid_connect_provider.this.arn

  namespace                        = "coder-ws-experiment"

  coder = {
    access_url = var.coder_access_url
    org_name = "experiment"
    image_repo                       = var.image_repo
    image_tag                        = var.image_tag
    rep_cnt = 4
    env_vars = {
      CODER_PROMETHEUS_ENABLE              = "true"
      CODER_PROMETHEUS_COLLECT_AGENT_STATS = "true"
      CODER_PROMETHEUS_COLLECT_DB_METRICS  = "true"
    }
  }

  svc_acc = {
    create = true
    name = "coder"
  }

  node_selector = local.node_selector
  tolerations   = local.tolerations
  affinity = local.affinity
}

module "demo-ws" {

  source = "../../../../../modules/k8s/bootstrap/coder-provisioner"

  release_name              = local.release_name
  chart_version             = var.addon_version
  chart_name                = local.chart_name
  cluster_name              = var.cluster_name
  cluster_oidc_provider_arn = data.aws_iam_openid_connect_provider.this.arn

  namespace                        = "coder-ws-demo"

  coder = {
    access_url = var.coder_access_url
    org_name = "demo"
    image_repo                       = var.image_repo
    image_tag                        = var.image_tag
    rep_cnt = 4
    env_vars = {
      CODER_PROMETHEUS_ENABLE              = "true"
      CODER_PROMETHEUS_COLLECT_AGENT_STATS = "true"
      CODER_PROMETHEUS_COLLECT_DB_METRICS  = "true"
    }
  }

  svc_acc = {
    create = true
    name = "coder"
  }

  node_selector = local.node_selector
  tolerations   = local.tolerations
  affinity = local.affinity
}


# module "default-ws-tagged" {

#   source                    = "../../../../../modules/k8s/bootstrap/coder-provisioner"

#   release_name              = local.release_name
#   chart_version             = var.addon_version
#   chart_name                = local.chart_name
#   cluster_name              = data.aws_eks_cluster.this.id
#   cluster_oidc_provider_arn = data.aws_iam_openid_connect_provider.this.arn

#   namespace = "coder-ws-tagged"

#   coder = {
#     access_url = var.coder_access_url
#     org_name = "coder"
#     image_repo                       = var.image_repo
#     image_tag                        = var.image_tag
#     ws_ns = ["coder-ws"]
#     prov_tags = {
#       region = "us-east-2"
#     }
#     rep_cnt = 2
#     env_vars = {
#       CODER_PROMETHEUS_ENABLE              = "true"
#       CODER_PROMETHEUS_COLLECT_AGENT_STATS = "true"
#       CODER_PROMETHEUS_COLLECT_DB_METRICS  = "true"
#     }
#   }

#   svc_acc = {
#     create = true
#     name = "coder"
#   }

#   node_selector = local.node_selector
#   tolerations   = local.tolerations
#   affinity = local.affinity
# }

# module "experiment-ws-tagged" {

#   source = "../../../../../modules/k8s/bootstrap/coder-provisioner"

#   release_name              = local.release_name
#   chart_version             = var.addon_version
#   chart_name                = local.chart_name
#   cluster_name              = var.cluster_name
#   cluster_oidc_provider_arn = data.aws_iam_openid_connect_provider.this.arn

#   namespace                        = "coder-ws-experiment-tagged"

#   coder = {
#     access_url = var.coder_access_url
#     org_name = "experiment"
#     image_repo                       = var.image_repo
#     image_tag                        = var.image_tag
#     ws_ns = ["coder-ws-experiment"]
#     prov_tags = {
#       region = "us-east-2"
#     }
#     rep_cnt = 2
#     env_vars = {
#       CODER_PROMETHEUS_ENABLE              = "true"
#       CODER_PROMETHEUS_COLLECT_AGENT_STATS = "true"
#       CODER_PROMETHEUS_COLLECT_DB_METRICS  = "true"
#     }
#   }

#   svc_acc = {
#     create = true
#     name = "coder"
#   }

#   node_selector = local.node_selector
#   tolerations   = local.tolerations
#   affinity = local.affinity
# }

# module "demo-ws-tagged" {

#   source = "../../../../../modules/k8s/bootstrap/coder-provisioner"

#   release_name              = local.release_name
#   chart_version             = var.addon_version
#   chart_name                = local.chart_name
#   cluster_name              = var.cluster_name
#   cluster_oidc_provider_arn = data.aws_iam_openid_connect_provider.this.arn

#   namespace                        = "coder-ws-demo-tagged"

#   coder = {
#     access_url = var.coder_access_url
#     org_name = "demo"
#     image_repo                       = var.image_repo
#     image_tag                        = var.image_tag
#     ws_ns = ["coder-ws-demo"]
#     prov_tags = {
#       region = "us-east-2"
#     }
#     rep_cnt = 2
#     env_vars = {
#       CODER_PROMETHEUS_ENABLE              = "true"
#       CODER_PROMETHEUS_COLLECT_AGENT_STATS = "true"
#       CODER_PROMETHEUS_COLLECT_DB_METRICS  = "true"
#     }
#   }

#   svc_acc = {
#     create = true
#     name = "coder"
#   }

#   node_selector = local.node_selector
#   tolerations   = local.tolerations
#   affinity = local.affinity
# }