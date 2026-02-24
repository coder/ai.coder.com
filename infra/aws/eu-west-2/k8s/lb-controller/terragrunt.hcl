include "root" {
  path = find_in_parent_folders("root.hcl")
  expose = true
}

dependencies {
  paths = [
    "../../eks",
    "../cert-manager"
  ]
}

inputs = {
  profile=include.root.locals.CODER_AWS_PROFILE
  region="eu-west-2"

  cluster_name=include.root.locals.CODER_CLUSTER_NAME

  addon_namespace=include.root.locals.LB_ADDON_NAMESPACE
  addon_version=include.root.locals.LB_ADDON_VERSION
  vpc_name=include.root.locals.CODER_VPC_NAME
  use_cert_manager=include.root.locals.LB_ADDON_USE_CERTMGR
}