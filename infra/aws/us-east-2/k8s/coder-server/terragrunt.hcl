include "root" {
  path = find_in_parent_folders("root.hcl")
  expose = true
}

dependencies {
  paths = [
    "../../eks", 
    "../../rds",
    "../litellm",
    "../karpenter", 
    "../lb-controller",
    "../cert-manager",
    "../other" # Deploy's auxillary manifests
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
  coder_experiments=jsondecode(include.root.locals.CODER_EXPERIMENTS)
  coder_builtin_provisioner_count=include.root.locals.CODER_BUILT_IN_PROVISIONER_COUNT

  coder_db_rds_name=include.root.locals.CODER_DB_RDS_ID
  coder_db_username=include.root.locals.CODER_DB_USERNAME
  coder_db_password=include.root.locals.CODER_DB_PASSWORD
  coder_db_name=include.root.locals.CODER_DB_NAME

  oidc_sign_in_text=include.root.locals.CODER_OIDC_SIGN_IN_TEXT
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

  image_repo=include.root.locals.CODER_IMAGE_REPO
  image_tag=include.root.locals.CODER_IMAGE_TAG
  addon_version=include.root.locals.CODER_ADDON_VERSION

  anthropic_llm_endpoint=include.root.locals.CODER_ANTHROPIC_LLM_ENDPOINT
  anthropic_llm_key=include.root.locals.CODER_ANTHROPIC_LLM_KEY

  openai_llm_endpoint=include.root.locals.CODER_OPENAI_LLM_ENDPOINT
  openai_llm_key=include.root.locals.CODER_OPENAI_LLM_KEY
}