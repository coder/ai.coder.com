provider "aws" {
  region  = var.region
  profile = var.profile
}

data "aws_region" "this" {}

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

data "aws_db_instance" "coder" {
  db_instance_identifier = var.coder_db_rds_name
}

data "aws_vpc" "this" {
  tags = {
    Name = var.vpc_name
  }
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.this.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.this.token
}

# ---------------------------------------------------------------------------
# Locals
# ---------------------------------------------------------------------------

locals {
  region       = data.aws_region.this.region
  account_id   = data.aws_caller_identity.this.account_id
  azs          = var.azs
  pub_subs     = [for az in local.azs : "${var.vpc_name}-public-${local.region}${az}"]
  release_name = "coder"
  namespace    = "coder"
  rds_db_name  = split(".", data.aws_db_instance.coder.endpoint)[0]

  common_name           = trimprefix(trimprefix(var.coder_access_url, "https://"), "http://")
  wildcard_name         = trimprefix(trimprefix(var.coder_wildcard_access_url, "https://"), "http://")
  ssl_vol_friendly_name = replace(local.common_name, ".", "-")
}

# ---------------------------------------------------------------------------
# Elastic IPs for NLB
# ---------------------------------------------------------------------------

resource "aws_eip" "coder" {
  count            = length(local.pub_subs)
  domain           = "vpc"
  public_ipv4_pool = "amazon"
  tags = {
    Name = "coder-eip-${count.index}"
  }
}

# ---------------------------------------------------------------------------
# IRSA: Provisioner policy (EC2 permissions for Terraform provisioners)
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "provisioner" {
  statement {
    effect = "Allow"
    actions = [
      "ec2:GetDefaultCreditSpecification",
      "ec2:DescribeIamInstanceProfileAssociations",
      "ec2:DescribeTags",
      "ec2:DescribeInstances",
      "ec2:DescribeInstanceTypes",
      "ec2:DescribeInstanceStatus",
      "ec2:CreateTags",
      "ec2:RunInstances",
      "ec2:DescribeInstanceCreditSpecifications",
      "ec2:DescribeImages",
      "ec2:ModifyDefaultCreditSpecification",
      "ec2:DescribeVolumes"
    ]
    resources = ["*"]
  }

  statement {
    effect = "Allow"
    actions = [
      "ec2:DescribeInstanceAttribute",
      "ec2:UnmonitorInstances",
      "ec2:TerminateInstances",
      "ec2:StartInstances",
      "ec2:StopInstances",
      "ec2:DeleteTags",
      "ec2:MonitorInstances",
      "ec2:CreateTags",
      "ec2:RunInstances",
      "ec2:ModifyInstanceAttribute",
      "ec2:ModifyInstanceCreditSpecification"
    ]
    resources = ["arn:aws:ec2:*:*:instance/*"]
  }
}

module "provisioner-policy" {
  count = var.coder_builtin_provisioner_count == 0 ? 0 : 1

  source      = "../../../../../../modules/security/policy"
  name        = "coder-srv"
  path        = "/${var.cluster_name}/${local.region}/"
  description = "Coder Terraform External Provisioner Policy"
  policy_json = data.aws_iam_policy_document.provisioner.json
}

# ---------------------------------------------------------------------------
# IRSA: RDS IAM auth policy
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "rds" {
  statement {
    effect  = "Allow"
    actions = ["rds-db:connect"]
    resources = [
      "arn:aws:rds-db:${local.region}:${local.account_id}:dbuser:${data.aws_db_instance.coder.resource_id}/${var.coder_db_username}"
    ]
  }
}

module "rds-policy" {
  source      = "../../../../../../modules/security/policy"
  name        = "coder-srv-${local.rds_db_name}"
  path        = "/${var.cluster_name}/${local.region}/"
  description = "Coder DB IAM Access Policy"
  policy_json = data.aws_iam_policy_document.rds.json
}

# ---------------------------------------------------------------------------
# IRSA: OIDC role for the Coder ServiceAccount
# ---------------------------------------------------------------------------

module "provisioner-oidc-role" {
  source       = "../../../../../../modules/security/role/access-entry"
  name         = "coder-srv"
  path         = "/${var.cluster_name}/${local.region}/"
  cluster_name = var.cluster_name
  policy_arns = merge({
    "AmazonEC2ReadOnlyAccess" = "arn:aws:iam::aws:policy/AmazonEC2ReadOnlyAccess"
    "CoderRDSDBPolicy"        = module.rds-policy.policy_arn
    }, var.coder_builtin_provisioner_count == 0 ? {} : {
    "TFProvisionerPolicy" = module.provisioner-policy[0].policy_arn
  })
  cluster_policy_arns = {}
  oidc_principals = {
    "${data.aws_iam_openid_connect_provider.this.arn}" = ["system:serviceaccount:*:*"]
  }
}

# ---------------------------------------------------------------------------
# ArgoCD Application — deploys the local wrapper Helm chart
# ---------------------------------------------------------------------------

resource "argocd_application" "coder" {
  metadata {
    name      = local.release_name
    namespace = "argocd"
  }

  spec {
    project = "default"

    destination {
      server    = "https://kubernetes.default.svc"
      namespace = local.namespace
    }

    source {
      repo_url        = "https://helm.coder.com/v2"
      chart           = "coder"
      target_revision = var.addon_version

      helm {
        release_name = local.release_name

        values = yamlencode({
          # Wrapper-level values
          namespace       = local.namespace
          createNamespace = true

          accessUrl   = var.coder_access_url
          wildcardUrl = var.coder_wildcard_access_url
          experiments = join(",", var.coder_experiments)

          provisionerDaemons = var.coder_builtin_provisioner_count

          tls = {
            enabled    = true
            secretName = local.ssl_vol_friendly_name
          }

          certificate = {
            enabled    = true
            commonName = local.common_name
            dnsNames   = [local.common_name, local.wildcard_name]
          }

          db = {
            url      = data.aws_db_instance.coder.endpoint
            username = var.coder_db_username
            password = var.coder_db_password
            name     = var.coder_db_name
            pgAuth   = "awsiamrds"
          }

          oidc = {
            enabled      = true
            issuerUrl    = var.coder_oidc_secret_issuer_url
            clientId     = var.coder_oidc_secret_client_id
            clientSecret = var.coder_oidc_secret_client_secret
            signInText   = var.oidc_sign_in_text
            iconUrl      = var.oidc_icon_url
            scopes       = var.oidc_scopes
            emailDomain  = var.oidc_email_domain
          }

          oauth2 = {
            enabled               = true
            defaultProviderEnable = false
            allowSignups          = true
            deviceFlow            = false
            allowedOrgs           = var.coder_github_allowed_orgs
            clientId              = var.coder_oauth_secret_client_id
            clientSecret          = var.coder_oauth_secret_client_secret
          }

          externalAuth = [{
            id           = "primary-github"
            type         = "github"
            clientId     = var.coder_github_external_auth_secret_client_id
            clientSecret = var.coder_github_external_auth_secret_client_secret
          }]

          aibridge = {
            enabled = true
          }

          prometheus = {
            enabled = true
          }

          service = {
            type              = "LoadBalancer"
            loadBalancerClass = "service.k8s.aws/nlb"
            annotations = {
              "service.beta.kubernetes.io/aws-load-balancer-nlb-target-type" = "ip"
              "service.beta.kubernetes.io/aws-load-balancer-scheme"          = "internet-facing"
              "service.beta.kubernetes.io/aws-load-balancer-attributes"      = "deletion_protection.enabled=false,load_balancing.cross_zone.enabled=true"
              "service.beta.kubernetes.io/aws-load-balancer-eip-allocations" = join(",", aws_eip.coder[*].allocation_id)
              "service.beta.kubernetes.io/aws-load-balancer-subnets"         = join(",", local.pub_subs)
            }
          }

          coder = {
            coder = {
              image = {
                repo = var.image_repo
                tag  = var.image_tag
              }
              replicaCount = length(local.pub_subs)
              resources = {
                requests = { cpu = "500m", memory = "2Gi" }
                limits   = { cpu = "2", memory = "2Gi" }
              }
              serviceAccount = {
                annotations = {
                  "eks.amazonaws.com/role-arn" = module.provisioner-oidc-role.role_arn
                }
                name = local.release_name
              }
              service = {
                enable = false
              }
              tls = {
                secretNames = [local.ssl_vol_friendly_name]
              }
              tolerations = [{
                key    = "platform"
                value  = "coder-server"
                effect = "NoSchedule"
              }]
              affinity = {
                nodeAffinity = {
                  requiredDuringSchedulingIgnoredDuringExecution = {
                    nodeSelectorTerms = [{
                      matchExpressions = [
                        {
                          key      = "topology.kubernetes.io/zone"
                          operator = "In"
                          values   = [for az in local.azs : "${local.region}${az}"]
                        },
                        {
                          key      = "node.coder.io/used-for"
                          operator = "In"
                          values   = ["coder-server"]
                        }
                      ]
                    }]
                  }
                }
                podAntiAffinity = {
                  preferredDuringSchedulingIgnoredDuringExecution = []
                  requiredDuringSchedulingIgnoredDuringExecution  = []
                }
              }
            }
          }
        })
      }
    }

    sync_policy {
      # automated {
      #   prune     = true
      #   self_heal = true
      # }
      # sync_options = ["CreateNamespace=true"]
      # retry {
      #   limit = "5"
      #   backoff {
      #     duration     = "30s"
      #     max_duration = "2m"
      #     factor       = "2"
      #   }
      # }
    }
  }
}
