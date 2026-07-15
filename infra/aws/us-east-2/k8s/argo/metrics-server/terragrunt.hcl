include "root" {
  path = find_in_parent_folders("root.hcl")
  expose = true
}

dependencies {
  paths = [
    "../../../eks", 
    "../../../rds",
    "../../karpenter", 
    "../../lb-controller",
    "../../cert-manager",
    "../../other" # Deploy's auxillary manifests
  ]
}

inputs = {
  profile=include.root.locals.CODER_AWS_PROFILE
  region=include.root.locals.CODER_AWS_REGION
  
  vpc_name=include.root.locals.CODER_VPC_NAME
  cluster_name=include.root.locals.CODER_CLUSTER_NAME
}