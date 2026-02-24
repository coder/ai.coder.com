include "root" {
  path = find_in_parent_folders("root.hcl")
  expose = true
}

dependencies {
  paths = [
    "../../eks",
    "../lb-controller",
    "../cert-manager",
    "../other",
    "../../../us-east-2/k8s/coder-server"
  ]
}

inputs = {
  profile=include.root.locals.CODER_AWS_PROFILE
  region="us-west-2"
  
  azs=jsondecode(include.root.locals.CODER_AWS_AZS)
  vpc_name=include.root.locals.CODER_VPC_NAME
  cluster_name=include.root.locals.CODER_CLUSTER_NAME

  coder_access_url=include.root.locals.CODER_DOMAIN_NAME
  coder_wildcard_access_url=include.root.locals.CODER_WILDCARD_URL

  coder_proxy_url="https://oregon-proxy.ai.coder.com"
  coder_proxy_wildcard_url="*.oregon-proxy.ai.coder.com"
  coder_proxy_name="us-west-2"
  coder_proxy_display_name="US West (Oregon)"
  coder_proxy_icon="/emojis/1f1fa-1f1f8.png"

  image_repo=include.root.locals.CODER_IMAGE_REPO
  image_tag=include.root.locals.CODER_IMAGE_TAG
  addon_version=include.root.locals.CODER_ADDON_VERSION

  coder_admin_email=include.root.locals.CODER_EMAIL
  coder_admin_password=include.root.locals.CODER_PASSWORD
}

