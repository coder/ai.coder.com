include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

include "config" {
  path   = find_in_parent_folders("config.hcl")
  expose = true
}

dependency "monitoring" {
  config_path = "../monitoring"
  mock_outputs = {
    prometheus_endpoint                         = "https://aps-workspaces.us-east-1.amazonaws.com/workspaces/ws-123456"
    grafana_endpoint                            = "https://g-1234567.grafana-workspace.us-east-1.amazonaws.com"
    aws_grafana_workspace_service_account_token = "abcdefg-1234567"
  }
}

dependencies {
  paths = [
    "../vpc",
    "../rds",
    "../eks",
    "../monitoring",
    "../k8s/argo/monitoring"
  ]
}

inputs = {
  profile = include.root.locals.CODER_AWS_PROFILE
  region  = include.config.locals.AWS_REGION

  cluster_name          = include.root.locals.CODER_CLUSTER_NAME
  vpc_name              = include.root.locals.CODER_VPC_NAME
  public_subnet_suffix  = include.root.locals.CODER_PUBLIC_SUBNET_SUFFIX
  private_subnet_suffix = include.root.locals.CODER_PRIVATE_SUBNET_SUFFIX

  coder_db_rds_id = include.root.locals.CODER_DB_RDS_ID

  prometheus_endpoint = dependency.monitoring.outputs.prometheus_endpoint
  grafana_endpoint    = dependency.monitoring.outputs.grafana_endpoint
  grafana_token       = dependency.monitoring.outputs.aws_grafana_workspace_service_account_token
  grafana_db_user     = include.root.locals.GRAFANA_DB_USERNAME
}