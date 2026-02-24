include "root" {
  path = find_in_parent_folders("root.hcl")
  expose = true
}

inputs = {
  profile=include.root.locals.CODER_AWS_PROFILE
  region=include.root.locals.CODER_AWS_REGION

  cluster_name=include.root.locals.CODER_CLUSTER_NAME
  vpc_name=include.root.locals.CODER_VPC_NAME
  vpc_cidr=include.root.locals.CODER_VPC_CIDR
  azs=include.root.locals.CODER_VPC_AZS
  nat_name=include.root.locals.CODER_VPC_NAT_NAME
  public_subnet_suffix=include.root.locals.CODER_PUBLIC_SUBNET_SUFFIX
  private_subnet_suffix=include.root.locals.CODER_PRIVATE_SUBNET_SUFFIX
}