include "root" {
  path = find_in_parent_folders("root.hcl")
  expose = true
}

inputs = {
  profile=include.root.locals.CODER_AWS_PROFILE
  region=include.root.locals.CODER_AWS_REGION

  loki_s3_bucket_name=include.root.locals.LOKI_S3_BUCKET_NAME
}