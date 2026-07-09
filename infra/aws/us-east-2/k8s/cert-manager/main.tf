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

module "cert-manager" {

  source = "../../../../../modules/k8s/bootstrap/cert-manager"

  cluster_name              = var.cluster_name
  cluster_oidc_provider_arn = data.aws_iam_openid_connect_provider.this.arn

  namespace    = var.addon_namespace
  helm_version = var.addon_version

  tolerations = [{
    key      = "CriticalAddonsOnly"
    operator = "Exists"
  }]
  affinity = {
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
}