include "root" {
  path = find_in_parent_folders("root.hcl")
  expose = true
}

dependencies {
  paths = [
    "../../eks",
    "../litellm",
    "../coder-server",
    "../kyverno",
    "../other" # Deploy's auxillary manifests
  ]
}

inputs = {
  profile=include.root.locals.CODER_AWS_PROFILE
  region=include.root.locals.CODER_AWS_REGION

  coder_access_url=include.root.locals.CODER_DOMAIN_NAME
  coder_admin_email=include.root.locals.CODER_EMAIL
  coder_admin_password=include.root.locals.CODER_PASSWORD
  
  cluster_name=include.root.locals.CODER_CLUSTER_NAME

  image_repo=include.root.locals.CODER_IMAGE_REPO
  image_tag=include.root.locals.CODER_IMAGE_TAG
  addon_version=include.root.locals.CODER_ADDON_VERSION
  logstream_addon_version=include.root.locals.CODER_LOGSTREAM_ADDON_VERSION
}