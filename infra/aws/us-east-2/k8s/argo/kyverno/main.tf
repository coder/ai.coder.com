provider "aws" {
  region  = var.region
  profile = var.profile
}

data "aws_caller_identity" "this" {}

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

locals {
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
  reg_mirror = "${data.aws_caller_identity.this.account_id}.dkr.ecr.${var.region}.amazonaws.com"
  reg_suffix = {
    "ghcr"       = "ghcr.io"
    "k8s"        = "registry.k8s.io"
    "quay"       = "quay.io"
    "docker-hub" = "index.docker.io"
    "ecr-public" = "public.ecr.aws"
  }
}

resource "kubernetes_manifest" "kyverno" {

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
      name        = "${var.region}.kyverno"
      namespace   = "argocd"
      labels      = {}
      annotations = {}
    }
    spec = {
      project = "default"
      source = {
        repoURL        = "https://github.com/coder/ai.coder.com"
        path           = "charts/kyverno"
        targetRevision = "main"
        helm = {
          releaseName = "kyverno"
          values = yamlencode({
            kyverno = {
              enabled = true
              global = {
                tolerations = [{
                  effect   = "NoSchedule"
                  key      = "CriticalAddonsOnly"
                  operator = "Exists"
                }]
              }
              config = {
                defaultRegistry               = "docker.io"
                enableDefaultRegistryMutation = true
                webhooks = {
                  namespacesSelector = {
                    matchExpressions = [{
                      key      = "kubernetes.io/metadata.name"
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
                replicas     = 3
                nodeAffinity = local.nodeAffinity
              }
              backgroundController = {
                replicas     = 2
                nodeAffinity = local.nodeAffinity
              }
              cleanupController = {
                replicas     = 2
                nodeAffinity = local.nodeAffinity
              }
              reportsController = {
                replicas     = 2
                nodeAffinity = local.nodeAffinity
              }
            }
            mutatingPolicy = {
              enabled     = true
              name        = "mutate-ws-image"
              matchPolicy = "Equivalent"
              annotations = {
                "helm.sh/hook"        = "post-install"
                "helm.sh/hook-weight" = "-5"
              }
              namespaceSelector = {
                matchExpressions = [{
                  key      = "kubernetes.io/metadata.name"
                  operator = "In"
                  values = [
                    "default",
                    "observability",
                    "ebs-controller",
                    "coder",
                    "coder-ws-demo",
                    "coder-ws-experiment",
                    "coder-ws"
                  ]
                }]
              }
              objectSelector = {
                matchExpressions = [
                  {
                    key      = "app.kubernetes.io/name"
                    operator = "NotIn"
                    values = [
                      # "coder-provisioner", 
                      # "coder"
                      "test"
                    ]
                  },
                  {
                    key      = "app.kubernetes.io/managed-by"
                    operator = "NotIn"
                    values = [
                      # "Helm",
                      "test"
                    ]
                  }
                ]
              }
              resourceRules = [
                {
                  apiGroups   = [""]
                  apiVersions = ["v1"]
                  operations  = ["CREATE", "UPDATE"]
                  resources   = ["pods"]
                }
              ]
              mutations = [for k in ["containers", "initContainers", "ephemeralContainers"] : {
                patchType = "JSONPatch"
                jsonPatch = {
                  expression = <<-EOT
                    object.spec.?${k}.orValue([]).map(c, 
                      %{for suffix, reg in local.reg_suffix~}
                      image(c.image).registry() == "${reg}" ? 
                      JSONPatch{
                        op: "replace",
                        path: "/spec/${k}/" + string(object.spec.?${k}.orValue([]).indexOf(c)) + "/image",
                        value: "${local.reg_mirror}" + "/" + "${suffix}" + "/" + string(image(c.image).repository()) + ":" + string(image(c.image).tag())
                      } :
                      %{endfor~}
                      null
                    ).filter(p, p != null)
                  EOT
                }
              }]
            }
            warmNodes = {
              enabled   = true
              namespace = "default"
              annotations = {
                "helm.sh/hook"        = "post-install"
                "helm.sh/hook-weight" = "-5"
              }
              labels = {
                "app.kubernetes.io/name" = "img-fetch"
              }
              selectorLabels = {
                "app.kubernetes.io/name" = "img-fetch"
              }
              terminationGracePeriodSeconds = 5
              pauseImage                    = "registry.k8s.io/pause:3.9"
              images = [
                "codercom/enterprise-java:latest",
                "codercom/enterprise-golang:latest",
                "codercom/enterprise-node:latest",
                "codercom/enterprise-base:ubuntu",
                "public.ecr.aws/f7a1d7a4/coder-aienv:1.1.4"
              ]
              daemonSets = [for k in ["coder-workspace", "coder-workspace-static"] : {
                name = "imgs-for-${k}"
                nodeSelector = {
                  "node.coder.io/instance"   = "coder-v2"
                  "node.coder.io/managed-by" = "karpenter"
                  "node.coder.io/name"       = "coder"
                  "node.coder.io/part-of"    = "coder"
                  "node.coder.io/used-for"   = k
                }
                tolerations = [{
                  key    = "dedicated"
                  value  = k
                  effect = "NoSchedule"
                }]
              }]
            }
          })
        }
      }
      destination = {
        server    = data.aws_eks_cluster.this.arn
        namespace = "kyverno"
      }
      syncPolicy = {
        syncOptions = [
          "CreateNamespace=true",
          "Delete=false",
          "ServerSideApply=true" # Avoid error here: https://github.com/argoproj/argo-cd/issues/11269
        ]
      }
    }
  }
}