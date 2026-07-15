include "root" {
  path = find_in_parent_folders("root.hcl")
  expose = true
}

dependencies {
  paths = ["../vpc"]
}

inputs = {
  profile=include.root.locals.CODER_AWS_PROFILE
  region=include.root.locals.CODER_AWS_REGION

  vpc_name=include.root.locals.CODER_VPC_NAME
  db_subnet_group_name=include.root.locals.CODER_DB_SUBNET_GROUP_NAME
  private_subnet_suffix=include.root.locals.CODER_PRIVATE_SUBNET_SUFFIX

  coder_db_rds_id=include.root.locals.CODER_DB_RDS_ID
  coder_db_name=include.root.locals.CODER_DB_NAME
  coder_username=include.root.locals.CODER_DB_USERNAME
}