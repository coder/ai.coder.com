#!/usr/bin/env bash
# Added proper error handling with set -euo pipefail for safer script execution
set -euo pipefail

# Validate required environment variables to prevent runtime errors
for var in LITELLM_URL LITELLM_MASTER_KEY USERNAME USER_EMAIL KEY_NAME KEY_DURATION AWS_SECRET_REGION AWS_SECRETS_MANAGER_ID; do
    if [[ -z "${!var:-}" ]]; then
        echo "Error: Required environment variable $var is not set" >&2
        exit 1
    fi
done

# Create user (ignore errors if already exists)
curl -L -X POST "$LITELLM_URL/user/new" \
    -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
    -H 'Content-Type: application/json' \
    -d "{\"username\":\"$USERNAME\",\"user_id\":\"$USERNAME\",\"email\":\"$USER_EMAIL\",\"key_alias\":\"$KEY_NAME\",\"duration\":\"$KEY_DURATION\"}" || true

# Delete existing key (ignore errors if doesn't exist)
curl -L -X POST "$LITELLM_URL/key/delete" \
    -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
    -H 'Content-Type: application/json' \
    -d "{\"key_aliases\":[\"$KEY_NAME\"]}" || true

# Generate new key with error handling and validation
if ! RESPONSE=$(curl -sS -L -X POST "$LITELLM_URL/key/generate" \
    -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
    -H 'Content-Type: application/json' \
    -d "{\"key_alias\":\"$KEY_NAME\",\"duration\":\"$KEY_DURATION\",\"metadata\":{\"user_id\":\"$USERNAME\"}}"); then
    echo "Error: Failed to generate LiteLLM key" >&2
    exit 1
fi

# Extract key with validation to ensure it's not empty or null
if ! NEW_LITELLM_USER_KEY=$(echo "$RESPONSE" | jq -r '.key'); then
    echo "Error: Failed to parse key from response" >&2
    exit 1
fi

if [[ -z "$NEW_LITELLM_USER_KEY" ]] || [[ "$NEW_LITELLM_USER_KEY" == "null" ]]; then
    echo "Error: Generated key is empty or null" >&2
    exit 1
fi

# Store secret with error handling
if ! aws secretsmanager put-secret-value \
    --region "$AWS_SECRET_REGION" \
    --secret-id "$AWS_SECRETS_MANAGER_ID" \
    --secret-string "{\"LITELLM_MASTER_KEY\":\"$NEW_LITELLM_USER_KEY\"}"; then
    # If update fails, try creating the secret
    if ! aws secretsmanager create-secret \
        --region "$AWS_SECRET_REGION" \
        --name "$AWS_SECRETS_MANAGER_ID" \
        --secret-string "{\"LITELLM_MASTER_KEY\":\"$NEW_LITELLM_USER_KEY\"}"; then
        echo "Error: Failed to store secret in AWS Secrets Manager" >&2
        exit 1
    fi
fi