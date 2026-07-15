include "root" {
  path = find_in_parent_folders("root.hcl")
  expose = true
}

dependencies {
  paths = [
    "../../../eks"
  ]
}

inputs = {
  profile=include.root.locals.CODER_AWS_PROFILE
  region=include.root.locals.CODER_AWS_REGION
  cluster_name=include.root.locals.CODER_CLUSTER_NAME
  cloudflare_api_token=include.root.locals.CF_TOKEN
  cloudflare_email=include.root.locals.CF_EMAIL
}