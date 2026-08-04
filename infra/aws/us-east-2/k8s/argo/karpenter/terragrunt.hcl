include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

include "config" {
  path   = find_in_parent_folders("config.hcl")
  expose = true
}

dependency "eks" {
  config_path = "../../../eks"
  mock_outputs = {
    eks_node_iam_role_name = "iam-role-name"
  }
}

dependencies {
  paths = [
    "../../../eks"
  ]
}

inputs = {
  profile = include.root.locals.CODER_AWS_PROFILE
  region  = include.config.locals.AWS_REGION

  cluster_name               = include.root.locals.CODER_CLUSTER_NAME
  cluster_node_iam_role_name = dependency.eks.outputs.eks_node_iam_role_name
  vpc_name                   = include.root.locals.CODER_VPC_NAME
}