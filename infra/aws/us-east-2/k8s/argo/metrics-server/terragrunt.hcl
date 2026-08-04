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
    "../../../rds",
    "../karpenter",
    "../lb-controller",
    "../cert-manager",
  ]
}

inputs = {
  profile = include.root.locals.CODER_AWS_PROFILE
  region  = include.config.locals.AWS_REGION

  vpc_name     = include.root.locals.CODER_VPC_NAME
  cluster_name = include.root.locals.CODER_CLUSTER_NAME
}