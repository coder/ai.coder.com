# Manual Trigger - 1

provider "aws" {
  region  = var.region
  profile = var.profile
}

locals {
  tags = {
    Name                     = var.name
    "karpenter.sh/discovery" = var.name
  }
  # Karpenter Security Group Discovery - https://karpenter.sh/v1.0/concepts/nodeclasses/#specsecuritygroupselectorterms
  tags_kptr_sg_discovery = {
    "karpenter.sh/discovery" = var.name
  }
  labels_system_node = {
    "scheduling.coder.com/pool" = "system"
  }
  taints_system = {
    key    = "CriticalAddonsOnly"
    effect = "NO_SCHEDULE"
  }
  tolerations_system = [{
    key      = "CriticalAddonsOnly"
    operator = "Exists"
  }]
}

resource "aws_iam_policy" "ecr-mirror" {
  name_prefix = "ecr-mirror-auto"
  description = "Allows ECR pull-through cache automation including repository creation"
  path        = "/${var.region}/auto-mode/"
  policy      = data.aws_iam_policy_document.ecr-mirror.json
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.24.0"

  vpc_id = data.aws_vpc.this.id
  subnet_ids = toset(concat(
    data.aws_subnets.private.ids
  ))

  name                    = var.name
  kubernetes_version      = var.eks_version
  endpoint_public_access  = true
  endpoint_private_access = true

  create_security_group         = true
  create_node_security_group    = true
  create_iam_role               = true
  node_security_group_tags      = local.tags_kptr_sg_discovery
  create_node_iam_role          = true
  node_iam_role_use_name_prefix = true

  node_iam_role_additional_policies = {
    "ECRMirrorPolicy" = aws_iam_policy.ecr-mirror.arn
  }

  create_auto_mode_iam_resources = true
  compute_config = {
    enabled = true
  }

  addons = {
    coredns = {
      before_compute = true
    }
    kube-proxy = {
      before_compute = true
    }
    vpc-cni = {
      before_compute = true
      configuration_values = jsonencode({
        enableNetworkPolicy = "true"
        nodeAgent = {
          enablePolicyEventLogs = "true"
        }
        env = {
          ENABLE_PREFIX_DELEGATION = "true"
          WARM_PREFIX_TARGET       = "1"
          WARM_IP_TARGET           = "0"
          AWS_VPC_K8S_CNI_LOGLEVEL = "DEBUG"
        }
      })
    }
  }

  attach_encryption_policy                 = false
  create_kms_key                           = false # Enable unless needed
  encryption_config                        = null
  enable_cluster_creator_admin_permissions = false
  enable_irsa                              = true

  tags = local.tags
}

# https://aws-controllers-k8s.github.io/docs/intro
# https://github.com/aws-controllers-k8s
# https://docs.aws.amazon.com/eks/latest/userguide/ack.html
module "eks-ack-capability" {
  source  = "terraform-aws-modules/eks/aws//modules/capability"
  version = "~> 21.24.0"

  name         = "eks-ack"
  cluster_name = module.eks.cluster_name
  type         = "ACK"

  # IAM Role/Policy
  iam_role_policies = {
    AdministratorAccess = "arn:aws:iam::aws:policy/AdministratorAccess"
  }

  tags = local.tags
}

locals {
  argocd_ns = "argocd"
}

# https://docs.aws.amazon.com/eks/latest/userguide/argocd.html
module "eks-argocd-capability" {
  source  = "terraform-aws-modules/eks/aws//modules/capability"
  version = "~> 21.24.0"

  type         = "ARGOCD"
  cluster_name = module.eks.cluster_name

  create_iam_role            = true
  iam_role_name              = "ArgoCDCapabilityRole-${module.eks.cluster_name}"
  iam_policy_path            = "/${var.region}/"
  iam_role_use_name_prefix   = false # Keep false to lookup. Differentiate via cluster name.
  iam_policy_use_name_prefix = true

  configuration = {
    argo_cd = {
      aws_idc = {
        idc_instance_arn = one(data.aws_ssoadmin_instances.this.arns)
        idc_region       = "us-east-1"
      }
      namespace = local.argocd_ns
      rbac_role_mapping = [{
        role = "ADMIN"
        identity = [{
          id   = data.aws_identitystore_group.aws_administrator.group_id
          type = "SSO_GROUP"
        }]
      }]
    }
  }

  # IAM Role/Policy
  iam_policy_statements = {
    ECRRead = {
      actions = [
        "ecr:GetAuthorizationToken",
        "ecr:BatchCheckLayerAvailability",
        "ecr:GetDownloadUrlForLayer",
        "ecr:BatchGetImage",
      ]
      resources = ["*"]
    }
  }

  tags = local.tags
}

##
# ReadOnly Access for SSO Admins
##
resource "aws_eks_access_entry" "admin-view" {
  principal_arn = "arn:aws:iam::${data.aws_caller_identity.me.account_id}:role/aws-reserved/sso.amazonaws.com/AWSReservedSSO_AWSAdministratorAccess_93fb9e9f44bd25bb"
  cluster_name  = module.eks.cluster_name
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "admin-view" {

  cluster_name  = module.eks.cluster_name
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSAdminViewPolicy"
  principal_arn = "arn:aws:iam::${data.aws_caller_identity.me.account_id}:role/aws-reserved/sso.amazonaws.com/AWSReservedSSO_AWSAdministratorAccess_93fb9e9f44bd25bb"

  access_scope {
    type = "cluster"
  }
}

##
# Access Entry for the Github Runner
##
resource "aws_eks_access_policy_association" "argocd" {
  cluster_name  = module.eks.cluster_name
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  principal_arn = module.eks-argocd-capability.iam_role_arn

  access_scope {
    type = "cluster"
  }
}

resource "aws_eks_access_entry" "runner" {
  principal_arn = "arn:aws:iam::${data.aws_caller_identity.me.account_id}:role/tf-runner-role"
  cluster_name  = module.eks.cluster_name
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "runner" {

  cluster_name  = module.eks.cluster_name
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  principal_arn = "arn:aws:iam::${data.aws_caller_identity.me.account_id}:role/tf-runner-role"

  access_scope {
    type = "cluster"
  }
}

resource "aws_eks_access_entry" "auto-mode" {
  principal_arn = module.eks.node_iam_role_arn
  cluster_name  = module.eks.cluster_name
  type          = "EC2"
}

resource "aws_eks_access_policy_association" "attach" {

  cluster_name  = module.eks.cluster_name
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSAutoNodePolicy"
  principal_arn = module.eks.node_iam_role_arn

  access_scope {
    type = "cluster"
  }
}

resource "aws_iam_instance_profile" "auto-mode" {
  name = module.eks.node_iam_role_name
  role = module.eks.node_iam_role_name
}

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    args        = ["eks", "get-token", "--cluster-name", var.name, "--region", var.region, "--profile", var.profile]
    command     = "aws"
  }
}

resource "kubernetes_secret_v1" "argocd-local-cluster-config" {
  depends_on = [module.eks-argocd-capability]
  metadata {
    name      = "local-cluster"
    namespace = local.argocd_ns
    labels = {
      "argocd.argoproj.io/secret-type" = "cluster"
    }
  }
  data = {
    name    = "local-cluster"
    server  = module.eks.cluster_arn
    project = "default"
  }
}

resource "kubernetes_secret_v1" "argocd-target-cluster-config-eu-west-2" {
  depends_on = [module.eks-argocd-capability]
  metadata {
    name      = "target-cluster-eu-west-2"
    namespace = local.argocd_ns
    labels = {
      "argocd.argoproj.io/secret-type" = "cluster"
    }
  }
  data = {
    name    = "local-cluster"
    server  = "arn:aws:eks:eu-west-2:${data.aws_caller_identity.me.account_id}:cluster/${module.eks.cluster_name}"
    project = "default"
  }
}

output "argocd_server_url" {
  value = module.eks-argocd-capability.argocd_server_url
}

output "eks_node_iam_role_name" {
  value = module.eks.node_iam_role_name
}