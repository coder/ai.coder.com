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

provider "kubernetes" {
  host                   = data.aws_eks_cluster.this.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.this.token
}

module "oidc-role" {
  source       = "../../../../../../modules/security/role/access-entry"
  name         = "aws-cw-observ"
  path         = "/${var.cluster_name}/${var.region}/"
  cluster_name = var.cluster_name
  policy_arns = {
    "CloudWatchAgentServerPolicy" = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
  }
  cluster_policy_arns = {}
  oidc_principals = {
    "${data.aws_iam_openid_connect_provider.this.arn}" = ["system:serviceaccount:*:*"]
  }
  tags = {}
}

resource "kubernetes_manifest" "aws-for-fluent-bit" {

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
      name        = "${var.region}.aws-for-fluent-bit"
      namespace   = "argocd"
      labels      = {}
      annotations = {}
    }
    spec = {
      project = "default"
      source = {
        repoURL        = "https://aws.github.io/eks-charts"
        chart          = "aws-for-fluent-bit"
        targetRevision = "0.2.0"
        helm = {
          releaseName = "aws-for-fluent-bit"
          values = yamlencode({
            nodeSelector = {}
            serviceAccount = {
              annotations = {
                "eks.amazonaws.com/role-arn" = module.oidc-role.role_arn
              }
            }
            cloudWatchLogs = {
              region           = var.region
              logGroupName     = "/aws/${var.region}/eks/fluentbit-cloudwatch/logs"
              logRetentionDays = 90
            }
            tolerations = [{
              key      = "CriticalAddonsOnly"
              operator = "Exists"
            }]
          })
        }
      }
      destination = {
        server    = data.aws_eks_cluster.this.arn
        namespace = "kube-system"
      }
      syncPolicy = {
        syncOptions = [
          "CreateNamespace=false",
          "Delete=confirm"
        ]
      }
    }
  }
}