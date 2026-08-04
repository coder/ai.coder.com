include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

include "config" {
  path   = find_in_parent_folders("config.hcl")
  expose = true
}

dependencies {
  paths = [
    "../../../eks",
    "../lb-controller",
    "../cert-manager",
    "../../../../us-east-2/k8s/argo/coder-server"
  ]
}

inputs = {
  profile           = include.root.locals.CODER_AWS_PROFILE
  region            = include.config.locals.AWS_REGION
  controller_region = include.config.locals.AWS_REGION_CONTROLLER

  azs          = jsondecode(include.root.locals.CODER_AWS_AZS)
  vpc_name     = include.root.locals.CODER_VPC_NAME
  cluster_name = include.root.locals.CODER_CLUSTER_NAME

  coder_access_url          = include.root.locals.CODER_DOMAIN_NAME
  coder_wildcard_access_url = include.root.locals.CODER_WILDCARD_URL

  coder_proxy_url          = "https://emea-proxy.ai.coder.com"
  coder_proxy_wildcard_url = "*.emea-proxy.ai.coder.com"
  coder_proxy_name         = "eu-west-2"
  coder_proxy_display_name = "Europe (London)"
  coder_proxy_icon         = "/emojis/1f1ec-1f1e7.png"

  image_repo = include.root.locals.CODER_IMAGE_REPO
  image_tag  = include.root.locals.CODER_IMAGE_TAG

  coder_token = include.root.locals.CODER_RUNNER_TOKEN
}

