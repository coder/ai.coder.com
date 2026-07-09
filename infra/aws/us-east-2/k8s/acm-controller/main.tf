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

module "oidc-role" {
  source       = "../../../../../modules/security/role/access-entry"
  name         = "acm-ctrl"
  path         = "/${var.cluster_name}/${var.region}/"
  cluster_name = var.cluster_name
  policy_arns = {
    "AmazonS3ReadOnlyAccess" = "arn:aws:iam::aws:policy/AWSCertificateManagerFullAccess"
  }
  cluster_policy_arns = {
    "AmazonEKSClusterAdminPolicy" = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy",
  }
  oidc_principals = {
    "${data.aws_iam_openid_connect_provider.this.arn}" = ["system:serviceaccount:*:*"]
  }
  tags = {}
}

resource "kubernetes_namespace_v1" "this" {

  count = var.create_namespace ? 1 : 0

  metadata {
    name = var.namespace
  }
}

resource "kubernetes_service_account_v1" "acm-ctrl" {
    metadata {
        name = "ack-acm-controller"
        namespace = try(kubernetes_namespace_v1.this[0].metadata[0].name, var.namespace)
        annotations = {
            "eks.amazonaws.com/role-arn" = module.oidc-role.role_arn
        }
    }
    automount_service_account_token = true
}

resource "helm_release" "acm-ctrl" {
  name             = var.release_name
  namespace        = try(kubernetes_namespace_v1.this[0].metadata[0].name, var.namespace)
  chart            = var.chart_name
  repository       = "oci://public.ecr.aws/aws-controllers-k8s/"
  create_namespace = false
  upgrade_install  = true
  skip_crds        = false
  wait             = true
  wait_for_jobs    = true
  version          = var.chart_version
  timeout          = 600

  values = [yamlencode({
    aws = {
      region = "us-east-1" # Required by CloudFront
    }
    serviceAccount = {
      create = false
      name = kubernetes_service_account_v1.acm-ctrl.metadata[0].name
    }
    deployment = {
      tolerations = [{
        effect = "NoSchedule"
        key = "CriticalAddonsOnly"
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
  })]
}