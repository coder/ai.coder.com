include "root" {
  path = find_in_parent_folders("root.hcl")
  expose = true
}

dependencies {
  paths = [
    "../../eks"
  ]
}

inputs = {
  profile=include.root.locals.CODER_AWS_PROFILE
  region=include.root.locals.CODER_AWS_REGION

  cluster_name=include.root.locals.CODER_CLUSTER_NAME

  addon_namespace=include.root.locals.CRTMGR_ADDON_NAMESPACE
  addon_version=include.root.locals.CRTMGR_ADDON_VERSION
}