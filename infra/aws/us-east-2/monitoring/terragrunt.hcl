include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

include "config" {
  path   = find_in_parent_folders("config.hcl")
  expose = true
}

dependencies {
  paths = ["../vpc"]
}

inputs = {
  profile = include.root.locals.CODER_AWS_PROFILE
  region  = include.config.locals.AWS_REGION

  vpc_name              = include.root.locals.CODER_VPC_NAME
  public_subnet_suffix  = include.root.locals.CODER_PUBLIC_SUBNET_SUFFIX
  private_subnet_suffix = include.root.locals.CODER_PRIVATE_SUBNET_SUFFIX
}