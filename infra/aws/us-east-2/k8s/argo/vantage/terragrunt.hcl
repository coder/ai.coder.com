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
  profile           = include.root.locals.CODER_AWS_PROFILE
  region            = include.config.locals.AWS_REGION
  cluster_name      = include.root.locals.CODER_CLUSTER_NAME
  vantage_api_token = include.root.locals.VANTAGE_API_TOKEN
}