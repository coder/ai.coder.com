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
    "../coder-server",
    "../kyverno",
    "../../other" # Deploy's auxillary manifests
  ]
}

inputs = {
  profile = include.root.locals.CODER_AWS_PROFILE
  region  = include.config.locals.AWS_REGION

  coder_access_url = include.root.locals.CODER_DOMAIN_NAME
  coder_token      = include.root.locals.CODER_RUNNER_TOKEN

  cluster_name = include.root.locals.CODER_CLUSTER_NAME

  image_repo = include.root.locals.CODER_IMAGE_REPO
  image_tag  = include.root.locals.CODER_IMAGE_TAG
}