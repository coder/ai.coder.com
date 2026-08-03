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

module "oidc-role" {
  source       = "../../../../../../modules/security/role/access-entry"
  name         = "ebs-ctrl"
  cluster_name = var.cluster_name
  path         = "/${var.cluster_name}/${data.aws_region.this.region}/"
  policy_arns = {
    "AmazonEBSCSIDriverPolicy" = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
  }
  cluster_policy_arns = {
    "AmazonEKSClusterAdminPolicy" = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  }
  oidc_principals = {
    "${data.aws_iam_openid_connect_provider.this.arn}" = ["system:serviceaccount:*:*"]
  }
  tags = {}
}

resource "kubernetes_manifest" "ebs-controller" {

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
      name        = "${var.region}.aws-ebs-csi-driver"
      namespace   = "argocd"
      labels      = {}
      annotations = {}
    }
    spec = {
      project = "default"
      source = {
        repoURL        = "https://github.com/coder/ai.coder.com"
        path           = "charts/aws-ebs-csi-driver"
        targetRevision = "main"
        helm = {
          releaseName = "aws-ebs-csi-driver"
          values = yamlencode({
            aws-ebs-csi-driver = {
              controller = {
                serviceAccount = {
                  # https://github.com/kubernetes-sigs/aws-ebs-csi-driver/blob/master/docs/install.md
                  annotations = {
                    "eks.amazonaws.com/role-arn" = module.oidc-role.role_arn
                  }
                }
                nodeSelector = {}
                tolerations = [{
                  key      = "CriticalAddonsOnly"
                  operator = "Exists"
                  }, {
                  key    = "dedicated"
                  value  = "general"
                  effect = "NoSchedule"
                }]
                topologySpreadConstraints = [{
                  topologyKey       = "topology.kubernetes.io/zone"
                  maxSkew           = 1
                  whenUnsatisfiable = "ScheduleAnyway"
                }]
                affinity = {
                  nodeAffinity = {
                    preferredDuringSchedulingIgnoredDuringExecution = []
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
                      podAffinityTerm = {
                        topologyKey = "topology.kubernetes.io/zone"
                        labelSelector = {
                          matchLabels = {
                            "app" = "ebs-csi-controller"
                          }
                        }
                      }
                      weight = 100
                    }]
                    requiredDuringSchedulingIgnoredDuringExecution = [{
                      topologyKey = "kubernetes.io/hostname"
                      labelSelector = {
                        matchLabels = {
                          "app" = "ebs-csi-controller"
                        }
                      }
                    }]
                  }
                }
              }
            }
            storageClasses = [
              {
                name      = "gp3"
                namespace = "default"
                annotations = {
                  "storageclass.kubernetes.io/is-default-class" = "true"
                }
                provisioner          = "ebs.csi.aws.com"
                volumeBindingMode    = "WaitForFirstConsumer"
                allowVolumeExpansion = true
                allowedTopologies = [{
                  matchLabelExpressions = [{
                    key    = "topology.ebs.csi.aws.com/zone"
                    values = [for az in var.azs : "${data.aws_region.this.region}${az}"]
                  }]
                }]
                parameters = {
                  type      = "gp3"
                  encrypted = "true"
                }
              },
              {
                name                 = "gp3"
                namespace            = "gp3-automode"
                annotations          = {}
                provisioner          = "ebs.csi.eks.amazonaws.com"
                volumeBindingMode    = "WaitForFirstConsumer"
                allowVolumeExpansion = true
                allowedTopologies = [{
                  matchLabelExpressions = [{
                    key    = "eks.amazonaws.com/compute-type"
                    values = ["auto"]
                  }]
                }]
                parameters = {
                  type      = "gp3"
                  encrypted = "true"
                }
              }
            ]
          })
        }
      }
      destination = {
        server    = data.aws_eks_cluster.this.arn
        namespace = "ebs-controller"
      }
      syncPolicy = {
        syncOptions = [
          "CreateNamespace=true",
          "Delete=false"
        ]
      }
    }
  }
}