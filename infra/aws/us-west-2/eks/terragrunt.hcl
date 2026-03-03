include "root" {
  path = find_in_parent_folders("root.hcl")
  expose = true
}

dependencies {
  paths = ["../vpc"]
}

inputs = {
  profile=include.root.locals.CODER_AWS_PROFILE
  region="us-west-2"
  azs=jsondecode(include.root.locals.CODER_AWS_AZS)

  name=include.root.locals.CODER_CLUSTER_NAME
  vpc_name=include.root.locals.CODER_VPC_NAME
  eks_version=include.root.locals.CODER_CLUSTER_VERSION
  instance_type=include.root.locals.CODER_CLUSTER_INSTANCE_TYPE
  public_subnet_suffix=include.root.locals.CODER_PUBLIC_SUBNET_SUFFIX
  private_subnet_suffix=include.root.locals.CODER_PRIVATE_SUBNET_SUFFIX
}