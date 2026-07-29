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
    "../../../eks"
  ]
}

inputs = {
  profile              = include.root.locals.CODER_AWS_PROFILE
  region               = include.config.locals.AWS_REGION
  controller_region    = include.config.locals.AWS_REGION_CONTROLLER
  cluster_name         = include.root.locals.CODER_CLUSTER_NAME
  cloudflare_api_token = include.root.locals.CF_TOKEN
  cloudflare_email     = include.root.locals.CF_EMAIL
}