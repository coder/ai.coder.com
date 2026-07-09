##
# Agents Provider Configuration
##

locals {
  credential_age = 30
}

resource "time_rotating" "bedrock" {
  rotation_days = local.credential_age
}

resource "aws_iam_user" "agent" {
  name = "coder-bedrock-provider"
  path = "/${var.region}/"
}

resource "aws_iam_user_policy_attachment" "test-attach" {
  user       = aws_iam_user.agent.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonBedrockLimitedAccess"
}

resource "aws_iam_access_key" "agent" {
  user = aws_iam_user.agent.name
  lifecycle {
    replace_triggered_by = [time_rotating.bedrock]
  }
}

resource "aws_iam_service_specific_credential" "bedrock" {
  service_name        = "bedrock.amazonaws.com"
  user_name           = aws_iam_user.agent.name
  credential_age_days = local.credential_age
  lifecycle {
    replace_triggered_by = [time_rotating.bedrock]
  }
}

resource "coderd_ai_provider" "openai-gpt-oss" {
  type         = "openai"
  name         = "aws-bedrock-openai-gpt-oss"
  display_name = "AWS Bedrock - OpenAI GPT OSS"
  enabled      = true
  base_url = "https://bedrock-mantle.${var.region}.api.aws/v1"

  api_key_wo         = aws_iam_service_specific_credential.bedrock.service_credential_secret
  api_key_wo_version = time_rotating.bedrock.unix
}

resource "coderd_ai_provider" "openai-gpt" {
  type         = "openai"
  name         = "aws-bedrock-openai-gpt"
  display_name = "AWS Bedrock - OpenAI GPT"
  enabled      = true
  # https://docs.aws.amazon.com/bedrock/latest/userguide/model-card-openai-gpt-55.html#model-card-openai-gpt-55-programmatic-access
  # https://docs.aws.amazon.com/bedrock/latest/userguide/model-card-openai-gpt-54.html#model-card-openai-gpt-54-programmatic-access
  base_url = "https://bedrock-mantle.${var.region}.api.aws/openai/v1"

  api_key_wo         = aws_iam_service_specific_credential.bedrock.service_credential_secret
  api_key_wo_version = time_rotating.bedrock.unix
}

resource "coderd_ai_provider" "openai-compatible" {
  type         = "openai-compat"
  name         = "aws-bedrock-openai-compatible"
  display_name = "AWS Bedrock - OpenAI Compatible"
  enabled      = true
  base_url     = "https://bedrock-mantle.${var.region}.api.aws"

  api_key_wo         = aws_iam_service_specific_credential.bedrock.service_credential_secret
  api_key_wo_version = time_rotating.bedrock.unix
}

resource "coderd_ai_provider" "openai-compatible-mantle" {
  type         = "openai-compat"
  name         = "aws-bedrock-openai-mantle-compatible"
  display_name = "AWS Bedrock Mantle - OpenAI Compatible"
  enabled      = true
  base_url     = "https://bedrock-mantle.${var.region}.api.aws/v1"

  api_key_wo         = aws_iam_service_specific_credential.bedrock.service_credential_secret
  api_key_wo_version = time_rotating.bedrock.unix
}

resource "coderd_ai_provider" "openai-compatible-runtime" {
  type         = "openai-compat"
  name         = "aws-bedrock-openai-runtime-compatible"
  display_name = "AWS Bedrock Runtime - OpenAI Compatible"
  enabled      = true
  base_url     = "https://bedrock-runtime.${var.region}.amazonaws.com/openai/v1"

  api_key_wo         = aws_iam_service_specific_credential.bedrock.service_credential_secret
  api_key_wo_version = time_rotating.bedrock.unix
}

resource "coderd_ai_provider" "bedrock" {
  type         = "bedrock"
  name         = "aws-bedrock"
  display_name = "AWS Bedrock"
  enabled      = true
  base_url     = "https://bedrock-runtime.${var.region}.amazonaws.com"

  settings = {
    bedrock = {
      model                  = "global.anthropic.claude-sonnet-4-5-20250929-v1:0"
      small_fast_model       = "global.anthropic.claude-haiku-4-5-20251001-v1:0"
      access_key_wo          = aws_iam_access_key.agent.id
      access_key_secret_wo   = aws_iam_access_key.agent.secret
      credentials_wo_version = time_rotating.bedrock.unix
    }
  }
}

locals {
  anthropic = {
    "global.anthropic.claude-opus-4-8" = {
      name         = "aws-anthropic-opus-4-8"
      display_name = "Claude Opus 4.8"
      enabled      = false
      model_config = {
        max_output_tokens = 8192
        temperature       = 1
        cost = {
          input_price_per_million_tokens  = "3"
          output_price_per_million_tokens = "15"
        }
        provider_options = {
          anthropic = {}
        }
      }
    }
    "global.anthropic.claude-opus-4-7" = {
      name         = "aws-anthropic-opus-4-7"
      display_name = "Claude Opus 4.7"
      enabled      = false
      model_config = {
        max_output_tokens = 8192
        temperature       = 1
        cost = {
          input_price_per_million_tokens  = "3"
          output_price_per_million_tokens = "15"
        }
        provider_options = {
          anthropic = {}
        }
      }
    }
    "global.anthropic.claude-opus-4-6-v1" = {
      name         = "aws-anthropic-opus-4-6"
      display_name = "Claude Opus 4.6"
      enabled      = false
      model_config = {
        max_output_tokens = 8192
        temperature       = 1
        cost = {
          input_price_per_million_tokens  = "3"
          output_price_per_million_tokens = "15"
        }
        provider_options = {
          anthropic = {}
        }
      }
    }
    "global.anthropic.claude-sonnet-4-6" = {
      name         = "aws-anthropic-sonnet-4-6"
      display_name = "Claude Sonnet 4.6"
      model_config = {
        max_output_tokens = 8192
        temperature       = 1
        cost = {
          input_price_per_million_tokens  = "3"
          output_price_per_million_tokens = "15"
        }
        provider_options = {
          anthropic = {}
        }
      }
    }
    # "global.anthropic.claude-fable-5" = {
    #     name = "aws-anthropic-fable-5"
    #     display_name = "Claude Fable 5"
    #     model_config = {
    #         max_output_tokens = 8192
    #         temperature       = 1
    #         cost = {
    #             input_price_per_million_tokens  = "3"
    #             output_price_per_million_tokens = "15"
    #         }
    #             provider_options = {
    #             anthropic = {}
    #         }
    #     }
    # }
    "global.anthropic.claude-sonnet-5" = {
      name         = "aws-anthropic-sonnet-5"
      display_name = "Claude Sonnet 5"
      model_config = {
        max_output_tokens = 8192
        temperature       = 1
        cost = {
          input_price_per_million_tokens  = "3"
          output_price_per_million_tokens = "15"
        }
        provider_options = {
          anthropic = {}
        }
      }
    }
  }

}

resource "coderd_ai_provider" "anthropic" {

  for_each = local.anthropic

  type         = "bedrock"
  name         = each.value.name
  display_name = "AWS Bedrock - ${each.value.display_name}"
  enabled      = try(each.value.enabled, true)
  base_url     = "https://bedrock-runtime.${var.region}.amazonaws.com"

  settings = {
    bedrock = {
      model                  = each.key
      small_fast_model       = "global.anthropic.claude-haiku-4-5-20251001-v1:0"
      access_key_wo          = aws_iam_access_key.agent.id
      access_key_secret_wo   = aws_iam_access_key.agent.secret
      credentials_wo_version = time_rotating.bedrock.unix
    }
  }
}

##
# Agent Models
##

resource "coderd_agents_model" "sonnet-4-5" {
  ai_provider_id = coderd_ai_provider.bedrock.id
  model          = "global.anthropic.claude-sonnet-4-5-20250929-v1:0"
  display_name   = "Claude Sonnet 4.5"
  enabled        = true
  context_limit  = 200000

  model_config = jsonencode({
    max_output_tokens = 8192
    temperature       = 1
    #   POST "https://bedrock-runtime.${var.region}.amazonaws.com/v1/messages": 400 Bad Request 
    #   { 
    #     "message":"`temperature` may only be set to 1 when thinking is enabled. Please consult our documentation at 
    #     https://docs.claude.com/en/docs/build-with-claude/extended-thinking#important-considerations-when-using-extended-thinking"
    #   }
    cost = {
      input_price_per_million_tokens  = "3"
      output_price_per_million_tokens = "15"
    }
    provider_options = {
      anthropic = {
        effort   = "low"
        thinking = { budget_tokens = 4096 }
      }
    }
  })
}

# Mark the Sonnet model as the deployment-wide default for Coder Agents.
# Setting a new default automatically demotes the previous one, so only a single
# coderd_default_agents_model resource should exist per deployment.
resource "coderd_default_agents_model" "default" {
  model_id = coderd_agents_model.sonnet-4-5.id
}

resource "coderd_agents_model" "haiku-4-5" {
  ai_provider_id = coderd_ai_provider.bedrock.id
  model          = "global.anthropic.claude-haiku-4-5-20251001-v1:0"
  display_name   = "Claude Haiku 4.5"
  enabled        = true
  context_limit  = 200000

  model_config = jsonencode({
    max_output_tokens = 8192
    temperature       = 1
    cost = {
      input_price_per_million_tokens  = "3"
      output_price_per_million_tokens = "15"
    }
    provider_options = {
      anthropic = {
        effort   = "low"
        thinking = { budget_tokens = 4096 }
      }
    }
  })
}

resource "coderd_agents_model" "anthropic-models" {

  for_each = local.anthropic

  ai_provider_id = coderd_ai_provider.anthropic[each.key].id
  model          = each.key
  display_name   = each.value.display_name
  enabled        = true
  context_limit  = 200000

  model_config = jsonencode(each.value.model_config)
}

resource "coderd_agents_model" "gpt-oss-120b" {
  ai_provider_id = coderd_ai_provider.openai-compatible-runtime.id
  model          = "openai.gpt-oss-120b-1:0"
  display_name   = "GPT OSS 120b"
  enabled        = true
  context_limit  = 200000

  model_config = jsonencode({
    max_output_tokens = 8192
    temperature       = 0.7
    cost = {
      input_price_per_million_tokens  = "3"
      output_price_per_million_tokens = "15"
    }
    provider_options = {
      anthropic = {
        effort   = "low"
        thinking = { budget_tokens = 4096 }
      }
    }
  })
}

resource "coderd_agents_model" "gpt-oss-20b" {
  ai_provider_id = coderd_ai_provider.openai-compatible-runtime.id
  model          = "openai.gpt-oss-20b-1:0"
  display_name   = "GPT OSS 20b"
  enabled        = true
  context_limit  = 200000

  model_config = jsonencode({
    max_output_tokens = 8192
    temperature       = 0.7
    cost = {
      input_price_per_million_tokens  = "3"
      output_price_per_million_tokens = "15"
    }
    provider_options = {
      anthropic = {
        effort   = "low"
        thinking = { budget_tokens = 4096 }
      }
    }
  })
}

resource "coderd_agents_model" "gpt-oss-safeguard-120b" {
  ai_provider_id = coderd_ai_provider.openai-gpt-oss.id
  model          = "openai.gpt-oss-safeguard-120b"
  display_name   = "GPT OSS Safeguard 120b"
  enabled        = true
  context_limit  = 200000

  model_config = jsonencode({
    max_output_tokens = 8192
    temperature       = 0.7
    cost = {
      input_price_per_million_tokens  = "3"
      output_price_per_million_tokens = "15"
    }
    provider_options = {
      anthropic = {
        effort   = "low"
        thinking = { budget_tokens = 4096 }
      }
    }
  })
}

resource "coderd_agents_model" "gpt-oss-safeguard-20b" {
  ai_provider_id = coderd_ai_provider.openai-gpt-oss.id
  model          = "openai.gpt-oss-safeguard-20b"
  display_name   = "GPT OSS Safeguard 20b"
  enabled        = true
  context_limit  = 200000

  model_config = jsonencode({
    max_output_tokens = 8192
    temperature       = 0.7
    cost = {
      input_price_per_million_tokens  = "3"
      output_price_per_million_tokens = "15"
    }
    provider_options = {
      anthropic = {
        effort   = "low"
        thinking = { budget_tokens = 4096 }
      }
    }
  })
}

resource "coderd_agents_model" "gpt-5-5" {
  ai_provider_id = coderd_ai_provider.openai-gpt.id
  model          = "openai.gpt-5.5"
  display_name   = "GPT 5.5"
  enabled        = false
  context_limit  = 200000

  model_config = jsonencode({
    max_output_tokens = 8192
    temperature       = 0.7
    cost = {
      input_price_per_million_tokens  = "3"
      output_price_per_million_tokens = "15"
    }
    provider_options = {
      openai = {
        reasoning_effort      = "low"
        max_completion_tokens = 8192
        parallel_tool_calls   = true
      }
    }
  })
}

resource "coderd_agents_model" "gpt-5-4" {
  ai_provider_id = coderd_ai_provider.openai-gpt.id
  model          = "openai.gpt-5.4"
  display_name   = "GPT 5.4"
  enabled        = false
  context_limit  = 200000

  model_config = jsonencode({
    max_output_tokens = 8192
    temperature       = 0.7
    cost = {
      input_price_per_million_tokens  = "3"
      output_price_per_million_tokens = "15"
    }
    provider_options = {
      openai = {
        reasoning_effort      = "low"
        max_completion_tokens = 8192
        parallel_tool_calls   = true
      }
    }
  })
}

resource "coderd_agents_model" "nova-2-lite" {
  # https://docs.aws.amazon.com/bedrock/latest/userguide/model-card-amazon-nova-2-lite.html#model-card-amazon-nova-2-lite-programmatic-access
  ai_provider_id = coderd_ai_provider.openai-compatible.id
  model          = "amazon.nova-2-lite-v1:0"
  display_name   = "Nova 2 Lite"
  enabled        = false
  context_limit  = 200000

  model_config = jsonencode({
    max_output_tokens = 8192
    temperature       = 0.7
    cost = {
      input_price_per_million_tokens  = "3"
      output_price_per_million_tokens = "15"
    }
    provider_options = {}
  })
}