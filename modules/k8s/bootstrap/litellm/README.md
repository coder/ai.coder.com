# LiteLLM Helm Chart Terraform Module

This Terraform module deploys [LiteLLM](https://github.com/BerriAI/litellm) as a Kubernetes Helm chart on AWS EKS. LiteLLM provides a unified proxy interface to multiple LLM providers, configured here to route requests to AWS Bedrock models (Claude Sonnet and Haiku) across multiple AWS regions.

## Overview

This module:
- Deploys LiteLLM proxy to an EKS cluster using the official Helm chart
  - https://artifacthub.io/packages/helm/litellm/litellm-helm
- Configures AWS IAM roles for service accounts (IRSA) for Bedrock access
- Sets up load balancer exposure via AWS Network Load Balancer
- Configures multi-region failover for Claude models
- Includes a PostgreSQL database for LiteLLM state management

## Architecture

```
┌─────────────┐
│   Client    │
└──────┬──────┘
       │
       ▼
┌─────────────────────────┐
│  AWS NLB (Port 4000)    │
└──────────┬──────────────┘
           │
           ▼
    ┌──────────────┐
    │   LiteLLM    │
    │   Proxy      │
    └──────┬───────┘
           │
           ├──► AWS Bedrock (us-east-2)
           ├──► AWS Bedrock (us-east-1)
           └──► AWS Bedrock (us-west-2)
```

## Prerequisites

- AWS EKS cluster (default: `aidemo-eks`)
- AWS CLI configured with appropriate profile
- Terraform >= 1.0
- Helm provider >= 3.1.1
- Kubernetes provider >= 3.0.1

## Variables

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `cluster_name` | string | `aidemo-eks` | Name of the EKS cluster |
| `cluster_region` | string | `us-east-2` | AWS region where the cluster is located |
| `cluster_profile` | string | `demo-coder` | AWS CLI profile to use |
| `namespace` | string | `litellm-tmp` | Kubernetes namespace for LiteLLM |
| `chart_version` | string | `0.1.830` | Version of the LiteLLM Helm chart |
| `cluster_oidc_provider_arn` | string | (see main.tf) | ARN of the EKS OIDC provider |

## Configured Models

The proxy is configured with the following AWS Bedrock models across multiple regions for high availability:

### Claude Sonnet 4.5
- Model: `anthropic.claude-sonnet-4-5-20250929-v1:0`
- Regions: `us-east-2`, `us-east-1`, `us-west-2`

### Claude 3 Haiku
- Model: `anthropic.claude-3-haiku-20240307-v1:0`
- Regions: `us-east-2`, `us-east-1`, `us-west-2`

## Usage

### Deploy the Module

```bash
terraform init
terraform plan
terraform apply
```

### Testing the Deployment

Use the included test script to verify the proxy is working:

```bash
./test.sh
```

This script configures Claude Code to use the LiteLLM proxy as the API endpoint.

### Get the Load Balancer URL

```bash
kubectl get svc -n litellm-tmp litellm
```

### Making API Requests

```bash
curl http://<load-balancer-url>:4000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer sk-2Uw00oiTMSxwEtHA19" \
  -d '{
    "model": "anthropic.claude-sonnet-4-5-20250929-v1:0",
    "messages": [{"role": "user", "content": "Hello!"}]
  }'
```

## Configuration Details

### IAM Role for Service Account (IRSA)

The module creates an IAM role with:
- AWS Bedrock Limited Access policy
- EKS Cluster Admin policy
- Trust relationship with the EKS OIDC provider

The service account annotation automatically injects AWS credentials into the pod.

### Service Configuration

- **Type**: LoadBalancer (AWS Network Load Balancer)
- **Port**: 4000
- **Scheme**: Internet-facing
- **Target Type**: Instance

### Database

- **Type**: PostgreSQL (standalone via Bitnami chart)
- **Purpose**: Stores LiteLLM configuration and state
- **Migration**: Automatic schema migration on deployment

### Security

- Master key authentication required for API access
- AWS credentials managed via IRSA (no static credentials)
- Secrets managed via Kubernetes secrets

## Files

- `main.tf` - Main Terraform configuration
- `values.yaml` - Helm chart values template
- `test.sh` - Quick test script for Claude Code integration

## Notes

- The load balancer is internet-facing by default
- Multi-region configuration provides automatic failover
- PostgreSQL credentials default to weak passwords and should be overridden in production
- The test script includes a hardcoded API key for testing purposes

## Cleanup

```bash
terraform destroy
```

This will remove the Helm release, namespace, and associated IAM resources.