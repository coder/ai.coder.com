include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

locals {
  AWS_REGION = "us-east-2"
}


dependencies {
  paths = ["../aws"]
}

inputs = {
  profile = include.root.locals.CODER_AWS_PROFILE
  region  = local.AWS_REGION

  coder_token       = include.root.locals.CODER_RUNNER_TOKEN
  coder_primary_url = include.root.locals.CODER_DOMAIN_NAME
}