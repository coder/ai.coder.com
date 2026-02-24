variable "region" {
  type = string
}

variable "profile" {
  type    = string
  default = "default"
}

variable "azs" {
  type = list(string)
  default = ["a", "c"]
}

variable "vpc_name" {
  type = string
}

variable "cluster_name" {
  type = string
}

variable "addon_version" {
  type    = string
  default = "2.25.1"
}

variable "coder_access_url" {
  type = string
}

variable "coder_wildcard_access_url" {
  type = string
}

variable "coder_experiments" {
  type    = list(string)
  default = []
}

variable "coder_github_allowed_orgs" {
  type    = list(string)
  default = []
}

variable "coder_builtin_provisioner_count" {
  type    = number
  default = 0
}

variable "coder_github_external_auth_secret_client_secret" {
  type      = string
  sensitive = true
}

variable "coder_github_external_auth_secret_client_id" {
  type      = string
  sensitive = true
}

variable "coder_oauth_secret_client_secret" {
  type      = string
  sensitive = true
}

variable "coder_oauth_secret_client_id" {
  type      = string
  sensitive = true
}

variable "coder_oidc_secret_client_secret" {
  type      = string
  sensitive = true
}

variable "coder_oidc_secret_client_id" {
  type      = string
  sensitive = true
}

variable "coder_oidc_secret_issuer_url" {
  type      = string
  sensitive = true
}

variable "coder_db_rds_name" {
  type = string
}

variable "coder_db_username" {
    type = string
}

variable "coder_db_password" {
    type = string
    sensitive = true
}

variable "coder_db_name" {
    type = string
}

variable "image_repo" {
  type      = string
  sensitive = true
}

variable "image_tag" {
  type    = string
  default = "latest"
}

variable "oidc_sign_in_text" {
  type = string
}

variable "oidc_icon_url" {
  type = string
}

variable "oidc_scopes" {
  type = list(string)
}

variable "oidc_email_domain" {
  type = string
}

variable "anthropic_llm_endpoint" {
  type      = string
  sensitive = true
}

variable "anthropic_llm_key" {
  type      = string
  sensitive = true
}

variable "openai_llm_endpoint" {
  type      = string
  sensitive = true
}

variable "openai_llm_key" {
  type      = string
  sensitive = true
}