include "root" {
  path = find_in_parent_folders("root.hcl")
  expose = true
}

dependencies {
  paths = ["../0-infra"]
}

inputs = {
  # Optional. Set if using Terragrunt.
  profile = include.root.locals.CODER_AWS_PROFILE
  region = include.root.locals.CODER_AWS_REGION
  domain_name = include.root.locals.CODER_DOMAIN_NAME
  azs = jsondecode(include.root.locals.CODER_AWS_AZS)
  coder_version = include.root.locals.CODER_VERSION
  coder_username = include.root.locals.CODER_DB_USERNAME
  coder_password = include.root.locals.CODER_DB_PASSWORD
  coder_license = include.root.locals.CODER_LICENSE
  coder_admin_email = include.root.locals.CODER_EMAIL
  coder_admin_username = include.root.locals.CODER_USERNAME
  coder_admin_password = include.root.locals.CODER_PASSWORD
}