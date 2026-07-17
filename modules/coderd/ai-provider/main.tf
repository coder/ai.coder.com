variable "region" {
  type    = string
  default = "us-east-1"
}

variable "credential_age" {
  type    = number
  default = 30
}

variable "ai_provider_type" {
  type    = string
  default = "anthropic"
}

variable "ai_provider_name" {
  type    = string
  default = "anthropic"
}

variable "ai_provider_display_name" {
  type    = string
  default = "Anthropic"
}

variable "ai_provider_enabled" {
  type    = bool
  default = true
}

variable "ai_provider_base_url" {
  type    = string
  default = "https://api.anthropic.com"
}

variable "ai_provider_settings" {
  type    = map(any)
  default = {}
}

variable "aws_bedrock_allowed_models" {
  type    = list(string)
  default = []
}

data "aws_caller_identity" "this" {}

resource "time_rotating" "bedrock" {
  rotation_days = var.credential_age
}

resource "aws_iam_user" "agent" {
  count = var.ai_provider_type != "bedrock" ? 1 : 0
  name = "coder-gateway-${var.ai_provider_name}"
  path = "/${var.region}/"
}

resource "aws_iam_role" "agent" {
  name_prefix        = "coder-gateway-${var.ai_provider_name}-"
  path               = "/"
  assume_role_policy = data.aws_iam_policy_document.assume-role.json
}

resource "aws_iam_policy" "bedrock" {
  name_prefix = "coder-gateway-${var.ai_provider_name}"
  policy      = data.aws_iam_policy_document.bedrock.minified_json
}

resource "aws_iam_user_policy_attachment" "bedrock" {
  count = var.ai_provider_type != "bedrock" ? 1 : 0
  policy_arn = aws_iam_policy.bedrock.arn
  user       = aws_iam_user.agent[0].name
}

resource "aws_iam_role_policy_attachment" "bedrock" {
  policy_arn = aws_iam_policy.bedrock.arn
  role       = aws_iam_role.agent.name
}

resource "aws_iam_access_key" "agent" {
  count = var.ai_provider_type != "bedrock" ? 1 : 0
  user = aws_iam_user.agent[0].name
  lifecycle {
    replace_triggered_by = [time_rotating.bedrock]
  }
}

resource "aws_iam_service_specific_credential" "bedrock" {
  count = var.ai_provider_type != "bedrock" ? 1 : 0
  service_name        = "bedrock.amazonaws.com"
  user_name           = aws_iam_user.agent[0].name
  credential_age_days = var.credential_age
  lifecycle {
    replace_triggered_by = [time_rotating.bedrock]
  }
}

resource "coderd_ai_provider" "bedrock-provider" {

  count = var.ai_provider_type == "bedrock" ? 1 : 0

  type         = var.ai_provider_type
  name         = var.ai_provider_name
  display_name = var.ai_provider_display_name
  enabled      = var.ai_provider_enabled
  base_url     = var.ai_provider_base_url

  settings = {
    bedrock = merge({
      role_arn = aws_iam_role.agent.arn
    }, var.ai_provider_settings)
  }
}

resource "coderd_ai_provider" "provider" {

  count = var.ai_provider_type != "bedrock" ? 1 : 0

  type         = var.ai_provider_type
  name         = var.ai_provider_name
  display_name = var.ai_provider_display_name
  enabled      = var.ai_provider_enabled
  base_url     = var.ai_provider_base_url

  api_key_wo         = var.ai_provider_type != "bedrock" ? aws_iam_service_specific_credential.bedrock[0].service_credential_secret : null
  api_key_wo_version = var.ai_provider_type != "bedrock" ? time_rotating.bedrock.unix : null

  settings = null
}

output "ai_provider_id" {
  value = var.ai_provider_type == "bedrock" ? coderd_ai_provider.bedrock-provider[0].id : coderd_ai_provider.provider[0].id
}