##
# System-Level Addons
##

module "karpenter" {

  source = "../../../modules/k8s/bootstrap/karpenter"

  cluster_name              = module.eks.cluster_name
  cluster_oidc_provider_arn = module.eks.oidc_provider_arn
  cluster_oidc_provider     = module.eks.oidc_provider

  namespace     = "karpenter"
  chart_version = "1.8.4"
  node_selector = local.labels_system_node
  tolerations = local.tolerations_system

  iam_role_use_name_prefix      = true
  node_iam_role_use_name_prefix = true
  replicas                      = 2
  karpenter_controller_role_policies = {
    "AmazonEFSCSIDriverPolicy" = "arn:aws:iam::aws:policy/service-role/AmazonEFSCSIDriverPolicy"
  }
}

module "metrics-server" {

  source = "../../../modules/k8s/bootstrap/metrics-server"

  namespace     = "metrics-server"
  chart_version = "3.13.0"
  node_selector = local.labels_system_node
  tolerations = local.tolerations_system
}

module "cert-manager" {

  source                    = "../../../modules/k8s/bootstrap/cert-manager"
  cluster_name              = module.eks.cluster_name
  cluster_oidc_provider_arn = module.eks.oidc_provider_arn

  namespace                     = "cert-manager"
  helm_version                  = "v1.18.2"
  tolerations = local.tolerations_system

  cf_config = {
    enabled = var.cf_config.enabled
    email   = var.cf_config.email
    token = var.cf_config.token
  }
  r53_config = {
    enabled = var.r53_config.enabled
    role_name = "crt-mgr"
    policy_name = "crt-mgr"
  }
}

module "lb-ctrl" {

  depends_on = [ module.cert-manager ]

  source                    = "../../../modules/k8s/bootstrap/lb-controller"
  cluster_name              = module.eks.cluster_name
  cluster_oidc_provider_arn = module.eks.oidc_provider_arn

  namespace           = "lb-ctrl"
  chart_version       = "1.13.2"
  node_selector    = local.labels_system_node
  tolerations = local.tolerations_system
  
  enable_cert_manager = true
  vpc_id              = module.vpc.vpc_id
  service_target_eni_sg_tags = {
    Name = module.eks.cluster_name
  }
  create_alb_class = false
}

module "ebs-ctrl" {

  source                    = "../../../modules/k8s/bootstrap/ebs-controller"
  cluster_name              = module.eks.cluster_name
  cluster_oidc_provider_arn = module.eks.oidc_provider_arn

  namespace     = "ebs-ctrl"
  chart_version = "2.22.1"
  node_selector = local.labels_system_node
  tolerations = local.tolerations_system
  replace       = true
}

module "ext-dns" {

  count = var.use_ext_dns ? 1 : 0
  depends_on = [ module.cert-manager ]

  source                    = "../../../modules/k8s/bootstrap/external-dns"
  cluster_name              = module.eks.cluster_name
  cluster_oidc_provider_arn = module.eks.oidc_provider_arn

  namespace     = "ext-dns"
  chart_version = "1.20.0"
  node_selector = local.labels_system_node
  tolerations = local.tolerations_system

  cf_config = {
    enabled = var.cf_config.enabled
    email   = var.cf_config.email
    token = var.cf_config.token
  }
  r53_config = {
    enabled = var.r53_config.enabled
    role_name = "crt-mgr"
    policy_name = "crt-mgr"
  }
}

module "ext-sec" {

  depends_on = [ module.cert-manager ]

  source                    = "../../../modules/k8s/bootstrap/external-secrets"
  cluster_name              = module.eks.cluster_name
  cluster_oidc_provider_arn = module.eks.oidc_provider_arn

  namespace     = "ext-sec"
  chart_version = "1.2.1"
  tolerations = local.tolerations_system
}