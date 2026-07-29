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

# https://github.com/aws-controllers-k8s/cloudfront-controller/blob/6628c7239a7257ae7f69822fa17175cbfe6415ef/config/iam/recommended-policy-arn
module "oidc-role" {
  source       = "../../../../../../modules/security/role/access-entry"
  name         = "acm-ctrl"
  path         = "/${var.cluster_name}/${var.region}/"
  cluster_name = var.cluster_name
  policy_arns = {
    "CloudFrontFullAccess" = "arn:aws:iam::aws:policy/CloudFrontFullAccess"
  }
  cluster_policy_arns = {
    "AmazonEKSClusterAdminPolicy" = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy",
  }
  oidc_principals = {
    "${data.aws_iam_openid_connect_provider.this.arn}" = ["system:serviceaccount:*:*"]
  }
  tags = {}
}

resource "kubernetes_manifest" "cloudfront-controller" {

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
      name        = "${var.region}.cloudfront-controller"
      namespace   = "argocd"
      labels      = {}
      annotations = {}
      finalizers = [
        "resources-finalizer.argocd.argoproj.io"
      ]
    }
    spec = {
      project = "default"
      source = {
        repoURL        = "oci://public.ecr.aws/aws-controllers-k8s/cloudfront-chart"
        chart          = "ack-cloudfront-controller"
        targetRevision = "1.5.0"
        helm = {
          releaseName = "cloudfront-ctrl"
          values = yamlencode({
            aws = {
              region = "us-east-1"
            }
            serviceAccount = {
              create = true
              annotations = {
                "eks.amazonaws.com/role-arn" = module.oidc-role.role_arn
              }
            }
            deployment = {
              tolerations = [{
                effect   = "NoSchedule"
                key      = "CriticalAddonsOnly"
                operator = "Exists"
              }]
              affinity = {
                nodeAffinity = {
                  requiredDuringSchedulingIgnoredDuringExecution = {
                    nodeSelectorTerms = [{
                      matchExpressions = [{
                        key      = "karpenter.sh/nodepool"
                        operator = "In"
                        values   = ["system"]
                      }]
                    }]
                  }
                }
              }
            }
          })
        }
      }
      destination = {
        server    = data.aws_eks_cluster.this.arn
        namespace = "cloudfront-controller"
      }
      syncPolicy = {
        syncOptions = [
          "CreateNamespace=true",
          "Delete=confirm"
        ]
      }
    }
  }
}