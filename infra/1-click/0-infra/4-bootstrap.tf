##
# System-Level Addons
##

module "karpenter" {
  source                    = "../../../modules/k8s/bootstrap/karpenter"

  cluster_name              = module.eks.cluster_name
  cluster_oidc_provider_arn = module.eks.oidc_provider_arn
  cluster_oidc_provider = module.eks.oidc_provider

  namespace     = "karpenter"
  chart_version = "1.8.4"
  node_selector = local.labels_system_node

  iam_role_use_name_prefix = true
  node_iam_role_use_name_prefix = true
  replicas = 2
  karpenter_controller_role_policies = {
    "AmazonEFSCSIDriverPolicy" = "arn:aws:iam::aws:policy/service-role/AmazonEFSCSIDriverPolicy"
  }
}

module "metrics-server" {

  # depends_on = [ module.karpenter ]

  source = "../../../modules/k8s/bootstrap/metrics-server"

  namespace     = "metrics-server"
  chart_version = "3.13.0"
  node_selector = local.labels_system_node
}

module "cert-manager" {

  # depends_on = [ module.karpenter ]

  source                    = "../../../modules/k8s/bootstrap/cert-manager"
  cluster_name              = module.eks.cluster_name
  cluster_oidc_provider_arn = module.eks.oidc_provider_arn

  namespace                     = "cert-manager"
  helm_version                  = "v1.18.2"
  use_cloudflare                = false
  use_route53                   = true
  create_default_cluster_issuer = false
}

module "lb-controller" {

  depends_on = [ module.cert-manager ]

  source                    = "../../../modules/k8s/bootstrap/lb-controller"
  cluster_name              = module.eks.cluster_name
  cluster_oidc_provider_arn = module.eks.oidc_provider_arn

  namespace           = "lb-ctrl"
  chart_version       = "1.13.2"
  enable_cert_manager = true
  vpc_id = module.vpc.vpc_id
  service_target_eni_sg_tags = {
    Name = module.eks.cluster_name
  }
  create_alb_class = false
  node_selector = local.labels_system_node
}

module "ebs-controller" {

  # depends_on = [ module.cert-manager ]

  source                    = "../../../modules/k8s/bootstrap/ebs-controller"
  cluster_name              = module.eks.cluster_name
  cluster_oidc_provider_arn = module.eks.oidc_provider_arn

  namespace     = "ebs-ctrl"
  chart_version = "2.22.1"
  node_selector = local.labels_system_node
  replace       = true
}

module "external-dns" {

  depends_on = [ module.cert-manager ]

  source                    = "../../../modules/k8s/bootstrap/external-dns"
  cluster_name              = module.eks.cluster_name
  cluster_oidc_provider_arn = module.eks.oidc_provider_arn

  namespace     = "external-dns"
  chart_version = "1.20.0"
  domain_name = var.domain_name
  node_selector = local.labels_system_node
}

module "external-secrets" {

  depends_on = [ module.cert-manager ]

  source                    = "../../../modules/k8s/bootstrap/external-secrets"
  cluster_name              = module.eks.cluster_name
  cluster_oidc_provider_arn = module.eks.oidc_provider_arn

  namespace                     = "external-secrets"
  chart_version                  = "1.2.1"
}