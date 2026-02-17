##
# Base Module
##

include "root" {
  path = find_in_parent_folders("root.hcl")
  expose = true
}

inputs = {
  profile = include.root.locals.CODER_AWS_PROFILE
  region = include.root.locals.CODER_AWS_REGION
  domain_name = include.root.locals.CODER_DOMAIN_NAME
  azs = jsondecode(include.root.locals.CODER_AWS_AZS)
  coder_username = include.root.locals.CODER_DB_USERNAME
  coder_password = include.root.locals.CODER_DB_PASSWORD
  grafana_username = include.root.locals.GRAFANA_DB_USERNAME
  grafana_password = include.root.locals.GRAFANA_DB_PASSWORD
}