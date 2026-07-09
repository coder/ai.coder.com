include "root" {
  path = find_in_parent_folders("root.hcl")
  expose = true
}

dependencies {
  paths = [
    "../../eks", 
    "../../rds", 
    "../../s3",
    "../cert-manager",
    "../lb-controller",
    "../litellm",
    "../coder-server",
    "../other" # Deploy's auxillary manifests
  ]
}

inputs = {
  profile=include.root.locals.CODER_AWS_PROFILE
  region=include.root.locals.CODER_AWS_REGION

  cluster_name=include.root.locals.CODER_CLUSTER_NAME

  chart_version=include.root.locals.CODER_OBSRV_CHART_VERSION
  namespace=include.root.locals.CODER_OBSRV_CHART_NAMESPACE

  domain_name=include.root.locals.GRAFANA_DOMAIN_NAME
  vpc_name=include.root.locals.CODER_VPC_NAME
  azs=include.root.locals.CODER_VPC_AZS
  private_subnet_suffix=include.root.locals.CODER_PRIVATE_SUBNET_SUFFIX

  loki_s3_bucket_name=include.root.locals.LOKI_S3_BUCKET_NAME
  loki_s3_bucket_region=include.root.locals.LOKI_S3_BUCKET_REGION

  coder_db_rds_id=include.root.locals.CODER_DB_RDS_ID
  coder_db_username=include.root.locals.CODER_DB_USERNAME
  coder_db_password=include.root.locals.CODER_DB_PASSWORD

  grafana_db_rds_id=include.root.locals.GRAFANA_DB_RDS_ID
  grafana_db_user=include.root.locals.GRAFANA_DB_USERNAME
  grafana_db_password=include.root.locals.GRAFANA_DB_PASSWORD

  grafana_auth_username=include.root.locals.GRAFANA_USERNAME
  grafana_auth_password=include.root.locals.GRAFANA_PASSWORD

  grafana_admin_username=include.root.locals.GRAFANA_ADMIN_USERNAME
  grafana_admin_password=include.root.locals.GRAFANA_ADMIN_PASSWORD
}