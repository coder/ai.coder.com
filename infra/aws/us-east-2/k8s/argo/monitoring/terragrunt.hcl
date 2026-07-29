include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

include "config" {
  path   = find_in_parent_folders("config.hcl")
  expose = true
}

dependency "monitoring" {
  config_path = "../../../monitoring"
  mock_outputs = {
    prometheus_endpoint = "https://aps-workspaces.us-east-1.amazonaws.com/workspaces/ws-123456"
  }
}

dependencies {
  paths = [
    "../../../eks",
    "../../../rds",
    "../../../monitoring",
    "../karpenter",
    "../lb-controller",
    "../cert-manager",
    "../../other" # Deploy's auxillary manifests
  ]
}

inputs = {
  profile = include.root.locals.CODER_AWS_PROFILE
  region  = include.config.locals.AWS_REGION

  vpc_name     = include.root.locals.CODER_VPC_NAME
  azs          = include.root.locals.CODER_VPC_AZS
  cluster_name = include.root.locals.CODER_CLUSTER_NAME

  loki_s3_bucket_name   = include.root.locals.LOKI_S3_BUCKET_NAME
  loki_s3_bucket_region = include.root.locals.LOKI_S3_BUCKET_REGION

  prometheus_endpoint = dependency.monitoring.outputs.prometheus_endpoint

  coder_db_rds_id = include.root.locals.CODER_DB_RDS_ID
  grafana_db_user = include.root.locals.GRAFANA_DB_USERNAME
}