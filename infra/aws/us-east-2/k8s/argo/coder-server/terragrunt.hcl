include "root" {
  path = find_in_parent_folders("root.hcl")
  expose = true
}

dependencies {
  paths = [
    "../../../eks", 
    "../../../rds",
    "../karpenter", 
    "../lb-controller",
    "../cert-manager",
    "../../other" # Deploy's auxillary manifests
  ]
}

inputs = {
  profile=include.root.locals.CODER_AWS_PROFILE
  region=include.root.locals.CODER_AWS_REGION
  
  azs=jsondecode(include.root.locals.CODER_AWS_AZS)
  vpc_name=include.root.locals.CODER_VPC_NAME
  cluster_name=include.root.locals.CODER_CLUSTER_NAME

  coder_access_url=include.root.locals.CODER_DOMAIN_NAME
  coder_wildcard_access_url=include.root.locals.CODER_WILDCARD_URL

  coder_db_rds_name=include.root.locals.CODER_DB_RDS_ID
  coder_db_username=include.root.locals.CODER_DB_USERNAME
  coder_db_name=include.root.locals.CODER_DB_NAME

  oidc_icon_url=include.root.locals.CODER_OIDC_ICON_URL
  oidc_scopes=include.root.locals.CODER_OIDC_SCOPES
  oidc_email_domain=include.root.locals.CODER_OIDC_EMAIL_DOMAIN
  coder_oidc_secret_issuer_url=include.root.locals.CODER_OIDC_ISSUER_URL
  coder_oidc_secret_client_id=include.root.locals.CODER_OIDC_CLIENT_ID
  coder_oidc_secret_client_secret=include.root.locals.CODER_OIDC_CLIENT_SECRET

  coder_oauth_secret_client_id=include.root.locals.CODER_GITHUB_OAUTH_CLIENT_ID
  coder_oauth_secret_client_secret=include.root.locals.CODER_GITHUB_OAUTH_CLIENT_SECRET
  coder_github_external_auth_secret_client_id=include.root.locals.CODER_GITHUB_EXTERN_AUTH_CLIENT_ID
  coder_github_external_auth_secret_client_secret=include.root.locals.CODER_GITHUB_EXTERN_AUTH_CLIENT_SECRET

  addon_version=include.root.locals.CODER_ADDON_VERSION
}