##
# System-Level Addons
##

module "metrics-server" {

  depends_on = [module.eks]
  source     = "../../../modules/k8s/bootstrap/metrics-server"

  namespace     = "metrics-server"
  chart_version = "3.13.0"
  tolerations   = local.tolerations_system
}

module "lb-ctrl" {

  source                    = "../../../modules/k8s/bootstrap/lb-controller"
  cluster_name              = module.eks.cluster_name
  cluster_oidc_provider_arn = module.eks.oidc_provider_arn

  namespace     = "lb-ctrl"
  chart_version = "3.0.0"
  vpc_id        = module.vpc.vpc_id
  tolerations   = local.tolerations_system
}

module "ebs-csi" {

  source                    = "../../../modules/k8s/bootstrap/ebs-csi"
  cluster_name              = module.eks.cluster_name
  cluster_oidc_provider_arn = module.eks.oidc_provider_arn

  namespace     = "ebs-csi"
  chart_version = "2.55.0"
  tolerations   = local.tolerations_system
  replace       = true
}