include "root" {
  path = find_in_parent_folders("root.hcl")
  expose = true
}

dependencies {
  paths = [
    "../../eks"
  ]
}

inputs = {
  profile=include.root.locals.CODER_AWS_PROFILE
  region=include.root.locals.CODER_AWS_REGION

  cluster_name=include.root.locals.CODER_CLUSTER_NAME

  vpc_name=include.root.locals.CODER_VPC_NAME
  azs=include.root.locals.CODER_VPC_AZS
  private_subnet_suffix=include.root.locals.CODER_PRIVATE_SUBNET_SUFFIX

  cloudflare_api_token=include.root.locals.CF_TOKEN
  cloudflare_secret_namespace=include.root.locals.CRTMGR_ADDON_NAMESPACE
  cloudflare_email=include.root.locals.CF_EMAIL
}