#!/usr/bin/env bash
# Added proper error handling with set -euo pipefail for safer script execution
set -euo pipefail

# Validate each required environment variable individually for better error reporting
for var in AWS_SECRET_REGION AWS_SECRETS_MANAGER_ID K8S_NAMESPACE; do
    if [[ -z "${!var:-}" ]]; then
        echo "Error: Required environment variable $var is not set" >&2
        exit 1
    fi
done

# Fetch secret with error handling to catch AWS API failures
if ! LITELLM_MASTER_KEY=$(aws secretsmanager get-secret-value \
    --region "$AWS_SECRET_REGION" \
    --secret-id "$AWS_SECRETS_MANAGER_ID" 2>/dev/null | jq -r '.SecretString' | jq -r '.LITELLM_MASTER_KEY'); then
    echo "Error: Failed to retrieve secret from AWS Secrets Manager" >&2
    exit 1
fi

# Validate secret value was retrieved to prevent empty secret creation
if [[ -z "$LITELLM_MASTER_KEY" ]] || [[ "$LITELLM_MASTER_KEY" == "null" ]]; then
    echo "Error: Retrieved secret is empty or null" >&2
    exit 1
fi

# Apply secret with error handling to catch kubectl failures
if ! kubectl create secret generic litellm -n "$K8S_NAMESPACE" -o yaml --dry-run=client \
    --from-literal=token="$LITELLM_MASTER_KEY" | kubectl apply -f -; then
    echo "Error: Failed to create/update Kubernetes secret" >&2
    exit 1
fi