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
    argocd_server_url = "https://123456abcdefg.eks-capabilities.us-east-1.amazonaws.com/"
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

  vpc_name          = include.root.locals.CODER_VPC_NAME
  cluster_name      = include.root.locals.CODER_CLUSTER_NAME
  argocd_server_url = dependency.eks.outputs.argocd_server_url
}