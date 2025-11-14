#!/usr/bin/env bash

# Exit on error, undefined variables, and pipe failures
set -euo pipefail

AWS_REGION=${AWS_REGION:-us-east-2}
IMAGE_REPO=${IMAGE_REPO:-ghcr.io/coder}
IMAGE_NAME=${IMAGE_NAME:-coder-preview}
IMAGE_TAG=${IMAGE_TAG:-latest}

# Validate required AWS_ACCOUNT_ID is set
if [ -z "${AWS_ACCOUNT_ID:-}" ]; then
    echo "Error: AWS_ACCOUNT_ID environment variable is required"
    exit 1
fi

IMAGE="${IMAGE_REPO}/${IMAGE_NAME}:${IMAGE_TAG}"

# Check if ECR repository exists, create if not
if ! aws ecr describe-repositories --region "$AWS_REGION" --repository-names "$IMAGE_NAME" 2>/dev/null; then
    echo "Repository $IMAGE_NAME not found, creating..."
    aws ecr create-repository --region "$AWS_REGION" --repository-name "$IMAGE_NAME" || { echo "Failed to create ECR repository"; exit 1; }
fi

# Login to ECR with error handling
if ! aws ecr get-login-password --region "$AWS_REGION" | docker login --username AWS --password-stdin "$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com"; then
    echo "Failed to login to ECR"
    exit 1
fi

# Pull, tag, and push image with error handling
if ! docker pull "$IMAGE"; then
    echo "Failed to pull image $IMAGE"
    exit 1
fi

if ! docker tag "$IMAGE" "$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$IMAGE_NAME:$IMAGE_TAG"; then
    echo "Failed to tag image"
    exit 1
fi

if ! docker push "$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$IMAGE_NAME:$IMAGE_TAG"; then
    echo "Failed to push image to ECR"
    exit 1
fi

echo "Successfully pushed $IMAGE to ECR"