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
  coder_password=include.root.locals.CODER_DB_PASSWORD


  grafana_db_rds_id=include.root.locals.GRAFANA_DB_RDS_ID
  grafana_db_name=include.root.locals.GRAFANA_DB_NAME
  grafana_username=include.root.locals.GRAFANA_DB_USERNAME
  grafana_password=include.root.locals.GRAFANA_DB_PASSWORD


  litellm_db_rds_id=include.root.locals.LITELLM_DB_RDS_ID
  litellm_db_name=include.root.locals.LITELLM_DB_NAME
  litellm_username=include.root.locals.LITELLM_DB_USERNAME
  litellm_password=include.root.locals.LITELLM_DB_ADMIN_PASSWORD

}