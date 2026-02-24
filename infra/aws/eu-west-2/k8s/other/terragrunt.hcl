include "root" {
  path = find_in_parent_folders("root.hcl")
  expose = true
}

dependencies {
  paths = [
    "../../eks",
    "../lb-controller",
    "../cert-manager",
  ]
}

inputs = {
  profile=include.root.locals.CODER_AWS_PROFILE
  region="eu-west-2"

  cluster_name=include.root.locals.CODER_CLUSTER_NAME

  azs=include.root.locals.CODER_VPC_AZS

  cloudflare_api_token=include.root.locals.CF_TOKEN
  cloudflare_secret_namespace=include.root.locals.CRTMGR_ADDON_NAMESPACE
  cloudflare_email=include.root.locals.CF_EMAIL
}