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

module "policy" {
  source      = "../../../../../../modules/security/policy"
  name        = "acm-ctrl"
  path        = "/${var.cluster_name}/${var.region}/"
  description = "ACM Controller Policy"
  policy_json = data.aws_iam_policy_document.this.json
}

module "oidc-role" {
  source       = "../../../../../../modules/security/role/access-entry"
  name         = "acm-ctrl"
  path         = "/${var.cluster_name}/${var.region}/"
  cluster_name = var.cluster_name
  policy_arns = {
    "ACMController" = module.policy.policy_arn
  }
  cluster_policy_arns = {
    "AmazonEKSClusterAdminPolicy" = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy",
  }
  oidc_principals = {
    "${data.aws_iam_openid_connect_provider.this.arn}" = ["system:serviceaccount:*:*"]
  }
  tags = {}
}

resource "kubernetes_manifest" "acm-controller" {

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
      name        = "${var.region}.acm-controller"
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
        repoURL        = "oci://public.ecr.aws/aws-controllers-k8s/acm-chart"
        chart          = "ack-acm-controller"
        targetRevision = "1.5.0"
        helm = {
          releaseName = "acm-ctrl"
          values = yamlencode({
            aws = {
              region = "us-east-1" # Required by CloudFront
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
        namespace = "acm-controller"
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