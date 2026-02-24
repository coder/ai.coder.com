include "root" {
  path = find_in_parent_folders("root.hcl")
  expose = true
}

dependencies {
  paths = [
    "../../eks",
    "../../rds",
    "../lb-controller",
    "../cert-manager",
    "../other" # Deploy's auxillary manifests
  ]
}

inputs = {
  profile=include.root.locals.CODER_AWS_PROFILE
  region=include.root.locals.CODER_AWS_REGION

  cluster_name=include.root.locals.CODER_CLUSTER_NAME

  addon_namespace=include.root.locals.LITELLM_ADDON_NAMESPACE
  addon_version=include.root.locals.LITELLM_ADDON_VERSION

  host_name=include.root.locals.LITELLM_DOMAIN_NAME
  vpc_name=include.root.locals.CODER_VPC_NAME
  azs=include.root.locals.CODER_VPC_AZS

  db_rds_id=include.root.locals.LITELLM_DB_RDS_ID
  db_admin_password=include.root.locals.LITELLM_DB_ADMIN_PASSWORD
  db_user_password=include.root.locals.LITELLM_DB_USER_PASSWORD

  gcloud_auth=include.root.locals.LITELLM_GCLOUD_AUTH
  litellm_master_key=include.root.locals.LITELLM_MASTER_KEY
}