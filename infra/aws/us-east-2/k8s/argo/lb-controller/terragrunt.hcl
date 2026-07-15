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
  vpc_name=include.root.locals.CODER_VPC_NAME
}