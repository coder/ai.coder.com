##
# Kubernetes Infrastructure
##

locals {
  # Karpenter Security Group Discovery - https://karpenter.sh/v1.0/concepts/nodeclasses/#specsecuritygroupselectorterms
  tags_kptr_sg_discovery = {
    "karpenter.sh/discovery" = "${local.formatted_name}-karpenter"
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

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.15.1"

  vpc_id = module.vpc.vpc_id

  # https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_cluster#vpc_config-1
  # https://docs.aws.amazon.com/eks/latest/userguide/network-reqs.html#network-requirements-subnets
  subnet_ids = toset(concat(
    module.vpc.private_subnets
  ))

  name = local.formatted_name

  kubernetes_version      = "1.34"
  endpoint_public_access  = true
  endpoint_private_access = true

  create_security_group         = true
  create_node_security_group    = true
  create_iam_role               = true
  node_security_group_tags      = local.tags_kptr_sg_discovery
  create_node_iam_role          = true
  node_iam_role_use_name_prefix = true

  compute_config = {
    enabled    = true
    node_pools = ["system"]
  }

  attach_encryption_policy                 = false
  create_kms_key                           = false # Enable unless needed
  encryption_config                        = null
  enable_cluster_creator_admin_permissions = true
  enable_irsa                              = true

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

  tags = {}
}

module "karpenter" {

  source = "../../../modules/k8s/bootstrap/karpenter"

  cluster_name              = module.eks.cluster_name
  cluster_oidc_provider_arn = module.eks.oidc_provider_arn
  cluster_oidc_provider     = module.eks.oidc_provider

  namespace     = "karpenter"
  chart_version = "1.9.0"

  node_selector = {
    "beta.kubernetes.io/os" = "linux"
    "kubernetes.io/os"      = null
  }
  tolerations     = local.tolerations_system
  topology_spread = []

  iam_role_use_name_prefix      = true
  node_iam_role_use_name_prefix = true
  replicas                      = 2
  karpenter_controller_role_policies = {
    "AmazonEFSCSIDriverPolicy" = "arn:aws:iam::aws:policy/service-role/AmazonEFSCSIDriverPolicy"
  }
}