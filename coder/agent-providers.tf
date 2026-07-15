data "aws_caller_identity" "this" {}

##
# Agents Provider Configuration
##

locals {
  anthropic = {
    "global.anthropic.claude-sonnet-4-5-20250929-v1:0" = {
      name         = "aws-bedrock-sonnet-4-5"
      display_name = "Claude Sonnet 4.5"
      allowed_models = [
        "arn:aws:bedrock:us-east-2:${data.aws_caller_identity.this.account_id}:inference-profile/global.anthropic.claude-sonnet-4-5-20250929-v1:0",
        "arn:aws:bedrock:*::foundation-model/anthropic.claude-sonnet-4-5-20250929-v1:0"
      ]
      enabled      = true
      model_config = {
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
      }
    }
    "global.anthropic.claude-sonnet-4-6" = {
      name         = "aws-bedrock-sonnet-4-6"
      display_name = "Claude Sonnet 4.6"
      allowed_models = [
        "arn:aws:bedrock:us-east-2:${data.aws_caller_identity.this.account_id}:inference-profile/global.anthropic.claude-sonnet-4-6",
        "arn:aws:bedrock:*::foundation-model/anthropic.claude-sonnet-4-6"
      ]
      enabled      = true
      model_config = {
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
      }
    }
    "global.anthropic.claude-sonnet-5" = {
      name         = "aws-bedrock-sonnet-5"
      display_name = "Claude Sonnet 5"
      allowed_models = [
        "arn:aws:bedrock:us-east-2:${data.aws_caller_identity.this.account_id}:inference-profile/global.anthropic.claude-sonnet-5",
        "arn:aws:bedrock:*::foundation-model/anthropic.claude-sonnet-5"
      ]
      enabled      = true
      model_config = {
        max_output_tokens = 8192
        temperature       = 1
        cost = {
          input_price_per_million_tokens  = "3"
          output_price_per_million_tokens = "15"
        }
        provider_options = {
          anthropic = {}

          ##
          # POST "https://bedrock-runtime.us-east-2.amazonaws.com/v1/messages": 
          # 400 Bad Request {"message":"\"thinking.type.enabled\" is not supported for this model. 
          # Use \"thinking.type.adaptive\" and \"output_config.effort\" to control thinking behavior."}
          ##

        }
      }
    }
    "global.anthropic.claude-haiku-4-5-20251001-v1:0" = {
      name         = "aws-bedrock-haiku-4-5"
      display_name = "Claude Haiku 4.5"
      allowed_models = [
        "arn:aws:bedrock:us-east-2:${data.aws_caller_identity.this.account_id}:inference-profile/global.claude-haiku-4-5-20251001-v1:0",
        "arn:aws:bedrock:*::foundation-model/anthropic.claude-haiku-4-5-20251001-v1:0"
      ]
      enabled      = true
      model_config = {
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
      }
    }
    "global.anthropic.claude-opus-4-8" = {
      name         = "aws-bedrock-opus-4-8"
      display_name = "Claude Opus 4.8"
      allowed_models = [
        "arn:aws:bedrock:us-east-2:${data.aws_caller_identity.this.account_id}:inference-profile/global.anthropic.claude-opus-4-8",
        "arn:aws:bedrock:*::foundation-model/anthropic.claude-opus-4-8"
      ]
      enabled      = true
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
      name         = "aws-bedrock-opus-4-7"
      display_name = "Claude Opus 4.7"
      allowed_models = [
        "arn:aws:bedrock:us-east-2:${data.aws_caller_identity.this.account_id}:inference-profile/global.anthropic.claude-opus-4-7",
        "arn:aws:bedrock:*::foundation-model/anthropic.claude-opus-4-7"
      ]
      enabled      = true
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
      name         = "aws-bedrock-opus-4-6"
      display_name = "Claude Opus 4.6"
      allowed_models = [
        "arn:aws:bedrock:us-east-2:${data.aws_caller_identity.this.account_id}:inference-profile/global.anthropic.claude-opus-4-6-v1",
        "arn:aws:bedrock:*::foundation-model/anthropic.claude-opus-4-6-v1"
      ]
      enabled      = true
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
    "global.anthropic.claude-opus-4-5-20251101-v1:0" = {
      name         = "aws-bedrock-opus-4-5"
      display_name = "Claude Opus 4.5"
      allowed_models = [
        "arn:aws:bedrock:us-east-2:${data.aws_caller_identity.this.account_id}:inference-profile/global.anthropic.claude-opus-4-5-20251101-v1:0",
        "arn:aws:bedrock:*::foundation-model/anthropic.claude-opus-4-5-20251101-v1:0"
      ]
      enabled      = true
      model_config = {
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
      }
    }
    # "global.anthropic.claude-fable-5" = {
    #     name = "aws-bedrock-fable-5"
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
  }
}

module "anthropic" {

  source = "./modules/coderd/ai-provider"

  for_each = local.anthropic

  region                   = var.region
  ai_provider_type         = "bedrock"
  ai_provider_name         = each.value.name
  ai_provider_display_name = "AWS Bedrock - ${each.value.display_name}"
  ai_provider_enabled      = try(each.value.enabled, true)
  ai_provider_base_url     = "https://bedrock-runtime.${var.region}.amazonaws.com"
  ai_provider_settings = {
    region           = "us-east-2"
    model            = each.key
    small_fast_model = "global.anthropic.claude-haiku-4-5-20251001-v1:0"
  }
  aws_bedrock_allowed_models = concat([
    "arn:aws:bedrock:us-east-2:${data.aws_caller_identity.this.account_id}:inference-profile/global.anthropic.claude-haiku-4-5-20251001-v1:0",
    "arn:aws:bedrock:*::foundation-model/anthropic.claude-haiku-4-5-20251001-v1:0"
  ], try(each.value.allowed_models, []))
}

# module "openai-gpt-oss" {

#   source = "./modules/coderd/ai-provider"

#   region                   = var.region
#   ai_provider_type         = "openai"
#   ai_provider_name         = "aws-bedrock-openai-gpt-oss"
#   ai_provider_display_name = "AWS Bedrock - OpenAI GPT OSS"
#   ai_provider_enabled      = true
#   ai_provider_base_url     = "https://bedrock-mantle.${var.region}.api.aws/v1"
#   aws_bedrock_allowed_models = [
#     "arn:aws:bedrock:us-east-2:${data.aws_caller_identity.this.account_id}:inference-profile/openai.gpt-oss-safeguard-120b",
#     "arn:aws:bedrock:us-east-2:${data.aws_caller_identity.this.account_id}:inference-profile/openai.gpt-oss-safeguard-20b",
#     "arn:aws:bedrock:*::foundation-model/openai.gpt-oss-safeguard-120b",
#     "arn:aws:bedrock:*::foundation-model/openai.gpt-oss-safeguard-20b",
#   ]


# }

# module "openai-gpt" {

#   source = "./modules/coderd/ai-provider"

#   region                   = var.region
#   ai_provider_type         = "openai"
#   ai_provider_name         = "aws-bedrock-openai-gpt"
#   ai_provider_display_name = "AWS Bedrock - OpenAI GPT"
#   ai_provider_enabled      = true
#   ai_provider_base_url     = "https://bedrock-mantle.${var.region}.api.aws/openai/v1"
#   # https://docs.aws.amazon.com/bedrock/latest/userguide/model-card-openai-gpt-55.html#model-card-openai-gpt-55-programmatic-access
#   # https://docs.aws.amazon.com/bedrock/latest/userguide/model-card-openai-gpt-54.html#model-card-openai-gpt-54-programmatic-access
# }

# module "openai-compatible" {

#   source = "./modules/coderd/ai-provider"

#   region                   = var.region
#   ai_provider_type         = "openai-compat"
#   ai_provider_name         = "aws-bedrock-openai-compatible"
#   ai_provider_display_name = "AWS Bedrock - OpenAI Compatible"
#   ai_provider_enabled      = true
#   ai_provider_base_url     = "https://bedrock-mantle.${var.region}.api.aws"
#   aws_bedrock_allowed_models = [
#     "arn:aws:bedrock:us-east-2:${data.aws_caller_identity.this.account_id}:inference-profile/amazon.nova-2-lite-v1:0",
#     "arn:aws:bedrock:*::foundation-model/amazon.nova-2-lite-v1:0",
#   ]
# }

# module "openai-compatible-mantle" {

#   source = "./modules/coderd/ai-provider"

#   region                   = var.region
#   ai_provider_type         = "openai-compat"
#   ai_provider_name         = "aws-bedrock-openai-mantle-compatible"
#   ai_provider_display_name = "AWS Bedrock Mantle - OpenAI Compatible"
#   ai_provider_enabled      = true
#   ai_provider_base_url     = "https://bedrock-mantle.${var.region}.api.aws/v1"
# }

# module "openai-compatible-runtime" {

#   source = "./modules/coderd/ai-provider"

#   region                   = var.region
#   ai_provider_type         = "openai-compat"
#   ai_provider_name         = "aws-bedrock-openai-runtime-compatible"
#   ai_provider_display_name = "AWS Bedrock Runtime - OpenAI Compatible"
#   ai_provider_enabled      = true
#   ai_provider_base_url     = "https://bedrock-runtime.${var.region}.amazonaws.com/openai/v1"
# }

##
# Agent Models
##

# Mark the Sonnet model as the deployment-wide default for Coder Agents.
# Setting a new default automatically demotes the previous one, so only a single
# coderd_default_agents_model resource should exist per deployment.
# resource "coderd_default_agents_model" "default" {
#   # model_id = coderd_agents_model.anthropic-models[keys(local.anthropic)[0]].id
#   model_id = coderd_agents_model.gpt-oss-20b.id
# }

resource "coderd_agents_model" "anthropic-models" {

  for_each = local.anthropic

  ai_provider_id = module.anthropic[each.key].ai_provider_id
  model          = each.key
  display_name   = each.value.display_name
  enabled        = true
  context_limit  = 20000

  model_config = jsonencode(each.value.model_config)
}

# resource "coderd_agents_model" "gpt-oss-120b" {
#   ai_provider_id = module.openai-compatible-runtime.ai_provider_id
#   model          = "openai.gpt-oss-120b-1:0"
#   display_name   = "GPT OSS 120b"
#   enabled        = true
#   context_limit  = 20000

#   model_config = jsonencode({
#     max_output_tokens = 8192
#     temperature       = 0.7
#     cost = {
#       input_price_per_million_tokens  = "3"
#       output_price_per_million_tokens = "15"
#     }
#     provider_options = {
#       anthropic = {
#         effort   = "low"
#         thinking = { budget_tokens = 4096 }
#       }
#     }
#   })
# }

# resource "coderd_agents_model" "gpt-oss-20b" {
#   ai_provider_id = module.openai-compatible-runtime.ai_provider_id
#   model          = "openai.gpt-oss-20b-1:0"
#   display_name   = "GPT OSS 20b"
#   enabled        = true
#   context_limit  = 20000

#   model_config = jsonencode({
#     max_output_tokens = 8192
#     temperature       = 0.7
#     cost = {
#       input_price_per_million_tokens  = "3"
#       output_price_per_million_tokens = "15"
#     }
#     provider_options = {
#       anthropic = {
#         effort   = "low"
#         thinking = { budget_tokens = 4096 }
#       }
#     }
#   })
# }

# resource "coderd_agents_model" "gpt-oss-safeguard-120b" {
#   ai_provider_id = module.openai-gpt-oss.ai_provider_id
#   model          = "openai.gpt-oss-safeguard-120b"
#   display_name   = "GPT OSS Safeguard 120b"
#   enabled        = true
#   context_limit  = 20000

#   model_config = jsonencode({
#     max_output_tokens = 8192
#     temperature       = 0.7
#     cost = {
#       input_price_per_million_tokens  = "3"
#       output_price_per_million_tokens = "15"
#     }
#     provider_options = {
#       anthropic = {
#         effort   = "low"
#         thinking = { budget_tokens = 4096 }
#       }
#     }
#   })
# }

# resource "coderd_agents_model" "gpt-oss-safeguard-20b" {
#   ai_provider_id = module.openai-gpt-oss.ai_provider_id
#   model          = "openai.gpt-oss-safeguard-20b"
#   display_name   = "GPT OSS Safeguard 20b"
#   enabled        = true
#   context_limit  = 20000

#   model_config = jsonencode({
#     max_output_tokens = 8192
#     temperature       = 0.7
#     cost = {
#       input_price_per_million_tokens  = "3"
#       output_price_per_million_tokens = "15"
#     }
#     provider_options = {
#       anthropic = {
#         effort   = "low"
#         thinking = { budget_tokens = 4096 }
#       }
#     }
#   })
# }

# resource "coderd_agents_model" "gpt-5-5" {
#   ai_provider_id = module.openai-gpt.ai_provider_id
#   model          = "openai.gpt-5.5"
#   display_name   = "GPT 5.5"
#   enabled        = false
#   context_limit  = 20000

#   model_config = jsonencode({
#     max_output_tokens = 8192
#     temperature       = 0.7
#     cost = {
#       input_price_per_million_tokens  = "3"
#       output_price_per_million_tokens = "15"
#     }
#     provider_options = {
#       openai = {
#         reasoning_effort      = "low"
#         max_completion_tokens = 8192
#         parallel_tool_calls   = true
#       }
#     }
#   })
# }

# resource "coderd_agents_model" "gpt-5-4" {
#   ai_provider_id = module.openai-gpt.ai_provider_id
#   model          = "openai.gpt-5.4"
#   display_name   = "GPT 5.4"
#   enabled        = false
#   context_limit  = 20000

#   model_config = jsonencode({
#     max_output_tokens = 8192
#     temperature       = 0.7
#     cost = {
#       input_price_per_million_tokens  = "3"
#       output_price_per_million_tokens = "15"
#     }
#     provider_options = {
#       openai = {
#         reasoning_effort      = "low"
#         max_completion_tokens = 8192
#         parallel_tool_calls   = true
#       }
#     }
#   })
# }

# resource "coderd_agents_model" "nova-2-lite" {
#   # https://docs.aws.amazon.com/bedrock/latest/userguide/model-card-amazon-nova-2-lite.html#model-card-amazon-nova-2-lite-programmatic-access
#   ai_provider_id = module.openai-compatible.ai_provider_id
#   model          = "amazon.nova-2-lite-v1:0"
#   display_name   = "Nova 2 Lite"
#   enabled        = false
#   context_limit  = 20000

#   model_config = jsonencode({
#     max_output_tokens = 8192
#     temperature       = 0.7
#     cost = {
#       input_price_per_million_tokens  = "3"
#       output_price_per_million_tokens = "15"
#     }
#     provider_options = {}
#   })
# }