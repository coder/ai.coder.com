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
  region="eu-west-2"
  
  vpc_name=include.root.locals.CODER_VPC_NAME
  cluster_name=include.root.locals.CODER_CLUSTER_NAME
}