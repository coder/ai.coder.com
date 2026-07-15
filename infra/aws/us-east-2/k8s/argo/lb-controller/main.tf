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

data "aws_region" "this" {}

data "aws_caller_identity" "this" {}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.this.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.this.token
}


locals {
  account_id = data.aws_caller_identity.this.account_id
  region     = data.aws_region.this.region
}

module "policy" {
  source      = "../../../../../../modules/security/policy"
  name        = "lb-ctrl"
  path        = "/${var.cluster_name}/${data.aws_region.this.region}/"
  description = "AWS Load Balancer Controller Policy"
  policy_json = data.aws_iam_policy_document.this.json
}

module "oidc-role" {
  source       = "../../../../../../modules/security/role/access-entry"
  name         = "lb-ctrl"
  path         = "/${var.cluster_name}/${data.aws_region.this.region}/"
  cluster_name = var.cluster_name
  policy_arns = {
    "AmazonEKSLoadBalancingPolicy" = "arn:aws:iam::aws:policy/AmazonEKSLoadBalancingPolicy",
    "ElasticLoadBalancingReadOnly" = "arn:aws:iam::aws:policy/ElasticLoadBalancingReadOnly",
    "LoadBalancerController"       = module.policy.policy_arn
  }
  cluster_policy_arns = {
    "AmazonEKSClusterAdminPolicy" = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy",
  }
  oidc_principals = {
    "${data.aws_iam_openid_connect_provider.this.arn}" = ["system:serviceaccount:*:*"]
  }
  tags = {}
}

resource "kubernetes_namespace_v1" "lb-controller" {
  metadata {
    name = "lb-controller"
  }
}

import {
  id = "lb-controller"
  to = kubernetes_namespace_v1.lb-controller
}

resource "kubernetes_manifest" "lb-controller" {

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
      name        = "aws-load-balancer-controller"
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
        repoURL        = "https://aws.github.io/eks-charts"
        chart          = "aws-load-balancer-controller"
        targetRevision = "1.13.2"
        helm = {
          values = yamlencode({
            clusterName = var.cluster_name
            serviceAccount = {
              create = true
              annotations = {
                "eks.amazonaws.com/role-arn" = module.oidc-role.role_arn
              }
              automountServiceAccountToken = true
              imagePullSecrets             = []
            }
            vpcId             = data.aws_vpc.this.id
            enableCertManager = true
            nodeSelector      = {}
            tolerations = [{
              key      = "CriticalAddonsOnly"
              operator = "Exists"
            }]
            topologySpreadConstraints = [{
              topologyKey       = "topology.kubernetes.io/zone"
              maxSkew           = 1
              whenUnsatisfiable = "ScheduleAnyway"
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
                preferredDuringSchedulingIgnoredDuringExecution = [{
                  weight = 100
                  podAffinityTerm = {
                    topologyKey = "topology.kubernetes.io/zone"
                    labelSelector = {
                      matchLabels = {
                        "app.kubernetes.io/name" = "aws-load-balancer-controller"
                      }
                    }
                  }
                }]
                requiredDuringSchedulingIgnoredDuringExecution = [{
                  topologyKey = "kubernetes.io/hostname"
                  labelSelector = {
                    matchLabels = {
                      "app.kubernetes.io/name" = "aws-load-balancer-controller"
                    }
                  }
                }]
              }
            }
            serviceTargetENISGTags = "Name=aidemo-eks-node"
            serviceMutatorWebhookConfig = {
              # Ref - https://github.com/awslabs/data-on-eks/issues/458
              failurePolicy = "Ignore"
            }
          })
        }
      }
      destination = {
        server    = data.aws_eks_cluster.this.arn
        namespace = kubernetes_namespace_v1.lb-controller.metadata[0].name
      }
      syncPolicy = {
        syncOptions = [
          "CreateNamespace=false",
          "Delete=false"
        ]
      }
    }
  }
}