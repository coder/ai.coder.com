# Route 53 Latency-Based Routing for Coder

This Terraform configuration sets up Route 53 latency-based routing for the Coder deployment in us-east-2.

## Overview

Latency-based routing automatically directs users to the AWS region that provides the lowest latency, improving the user experience by connecting them to the nearest deployment.

## Features

- **Latency-based routing**: Routes users to the closest region automatically
- **Health checks**: Monitors endpoint health and routes around failures
- **Wildcard DNS**: Supports workspace application subdomains
- **Automatic NLB discovery**: Retrieves NLB hostname from Kubernetes service

## Prerequisites

1. Hosted Zone ID for coderdemo.io (already configured: Z080884039133KJPAGA3S)
2. Running EKS cluster with Coder deployed
3. Network Load Balancer created via Kubernetes service

## Deployment

1. Create terraform.tfvars from the example:

```bash
cp terraform.tfvars.example terraform.tfvars
```

2. Update terraform.tfvars with your cluster name:

```hcl
cluster_name = "your-cluster-name"
```

3. Initialize and apply:

```bash
terraform init
terraform plan
terraform apply
```

## How It Works

1. The configuration queries the Kubernetes service to get the NLB hostname
2. Creates Route 53 A records with latency-based routing policy
3. Sets up health checks to monitor endpoint availability
4. Configures both main domain and wildcard records

## Health Checks

Health checks monitor the `/api/v2/buildinfo` endpoint on port 443 (HTTPS):

- **Interval**: 30 seconds
- **Failure threshold**: 3 consecutive failures
- **Latency measurement**: Enabled for monitoring

## Records Created

- `coderdemo.io` - Main domain with latency routing
- `*.coderdemo.io` - Wildcard for workspace applications

## Important Notes

- Deploy this configuration in **both** us-east-2 and us-west-2 with different set_identifiers
- Each region's configuration points to its local NLB
- Route 53 automatically routes based on measured latency
- Health checks ensure failover if one region becomes unhealthy
