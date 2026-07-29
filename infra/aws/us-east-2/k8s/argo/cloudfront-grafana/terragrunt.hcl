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
    grafana_endpoint = "https://g-1234567.grafana-workspace.us-east-1.amazonaws.com"
  }
}

dependencies {
  paths = [
    "../../../eks",
    "../../../monitoring"
  ]
}

inputs = {
  profile = include.root.locals.CODER_AWS_PROFILE
  region  = include.config.locals.AWS_REGION

  vpc_name         = include.root.locals.CODER_VPC_NAME
  cluster_name     = include.root.locals.CODER_CLUSTER_NAME
  grafana_endpoint = dependency.monitoring.outputs.grafana_endpoint
}