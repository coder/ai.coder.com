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

resource "kubernetes_namespace_v1" "this" {

  count = var.create_namespace ? 1 : 0

  metadata {
    name = var.namespace
  }
}

locals {
  nodeAffinity = {
    requiredDuringSchedulingIgnoredDuringExecution = {
      nodeSelectorTerms = [{
        matchExpressions = [{
          key = "karpenter.sh/nodepool"
          operator = "In"
          values = ["system"]
        }]
      }]
    }
  }
}

resource "helm_release" "kyverno" {
  name             = var.release_name
  namespace        = try(kubernetes_namespace_v1.this[0].metadata[0].name, var.namespace)
  chart            = var.chart_name
  repository       = "https://kyverno.github.io/kyverno/"
  create_namespace = false
  upgrade_install  = true
  skip_crds        = false
  wait             = true
  wait_for_jobs    = true
  version          = var.chart_version
  timeout          = 600

  values = [yamlencode({

    global = {
      tolerations = [{
        effect = "NoSchedule"
        key = "CriticalAddonsOnly"
        operator = "Exists"
      }]
    }

    config = {
      defaultRegistry = "docker.io"
      enableDefaultRegistryMutation = true
      webhooks = {
        namespacesSelector = {
          matchExpressions = [{
            key = "kubernetes.io/metadata.name"
            operator = "NotIn"
            values = [
              "kube-system",
            ]
          }]
        }
      }
    }
    
    crds = {
      migration = {
        nodeAffinity = local.nodeAffinity
      }
    }
    admissionController = {
      replicas = 3
      nodeAffinity = local.nodeAffinity
    }
    backgroundController = {
      replicas = 2
      nodeAffinity = local.nodeAffinity
    }
    cleanupController = {
      replicas = 2
      nodeAffinity = local.nodeAffinity
    }
    reportsController = {
      replicas = 2
      nodeAffinity = local.nodeAffinity
    }
  })]
}