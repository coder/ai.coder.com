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

data "aws_vpc" "this" {
  tags = {
    Name = var.vpc_name
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

locals {
  release_name = "aws-load-balancer-controller"
}

module "lb-controller" {
  source                    = "../../../../../modules/k8s/bootstrap/lb-controller"
  cluster_name              = data.aws_eks_cluster.this.name
  cluster_oidc_provider_arn = data.aws_iam_openid_connect_provider.this.arn

  release_name        = local.release_name
  namespace           = var.addon_namespace
  chart_version       = var.addon_version
  enable_cert_manager = var.use_cert_manager
  vpc_id              = data.aws_vpc.this.id

  tolerations = [{
    key      = "CriticalAddonsOnly"
    operator = "Exists"
  }]
  affinity = {
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
    podAntiAffinity = {
      requiredDuringSchedulingIgnoredDuringExecution = [{
        topologyKey = "kubernetes.io/hostname"
        weight = 100
        podAffinityTerm = {
          labelSelector = {
            matchExpressions = [{
              key      = "app.kubernetes.io/name"
              operator = "In"
              values   = [local.release_name]
            }]
          }
        }
      }]
    }
  }
  service_target_eni_sg_tags = {
    Name = "aidemo-eks-node"
  }
}