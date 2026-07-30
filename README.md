# AI Demo Environment (ai.coder.com)

Welcome to the AI Demo Environment's GitHub repository! 

This project powers [ai.coder.com](https://ai.coder.com), allowing users to experiment with the latest AI features in Coder.

---

## Getting Started

> [!IMPORTANT] Before accessing the deployment, make sure you've been invited to the "coder-contrib" GitHub organization. If not, reach out to `jullian@coder.com` with your GitHub handle. Coder employees should already have access.

### Accessing the Deployment

Get Started Here 👉 [https://ai.coder.com](https://ai.coder.com)

**Login Flow**

- **Non-Coder Employee**: Select "GitHub" and login with your GitHub account
- **Coder Employee**: Select "Okta" and login with your Okta account


--- 

## Architecture Overview

This deployment uses **Terragrunt** for infrastructure management and **ArgoCD** for Kubernetes application delivery.

### Infrastructure Components

**Regions:**
- **us-east-2** (Primary): Full deployment with Coder server, RDS database, monitoring, and Grafana
- **eu-west-2** (Proxy): Regional proxy deployment for improved latency

**Core Infrastructure:**
- **VPC**: Custom VPC with public and private subnets across multiple availability zones
- **EKS**: Amazon EKS clusters with Karpenter for dynamic node provisioning
- **RDS**: PostgreSQL database (us-east-2 only)
- **S3**: Terraform state backend
- **Monitoring**: CloudWatch integration with Grafana (us-east-2 only)

### Kubernetes Applications (via ArgoCD)

Applications are deployed using ArgoCD and managed through Terraform-generated ArgoCD Application manifests in `infra/aws/{region}/k8s/argo/`:

**Bootstrap Components:**
- AWS Load Balancer Controller
- AWS EBS CSI Driver
- Cert Manager
- External Secrets Operator
- Karpenter
- Metrics Server
- AWS for Fluent Bit (logging)

**Coder Components:**
- Coder Server (us-east-2)
- Coder Proxy (eu-west-2)
- Coder Provisioner/Workspace

**Additional Services:**
- Vantage (cost monitoring)
- Monitoring stack (us-east-2)
- Kyverno (policy engine, us-east-2)
- CloudFront controllers (us-east-2)

### Deployment Structure

```
infra/
├── root.hcl                    # Root Terragrunt configuration
├── coder/                      # Coder-specific Terraform config
├── aws/
│   ├── us-east-2/              # Primary region
│   │   ├── config.hcl          # Region-specific config
│   │   ├── vpc/                # VPC infrastructure
│   │   ├── eks/                # EKS cluster
│   │   ├── rds/                # PostgreSQL database
│   │   ├── s3/                 # S3 buckets
│   │   ├── monitoring/         # CloudWatch resources
│   │   ├── grafana/            # Grafana resources
│   │   └── k8s/
│   │       ├── argo/           # ArgoCD Application manifests
│   │       └── other/          # Additional K8s resources
│   └── eu-west-2/              # Proxy region
│       ├── config.hcl
│       ├── vpc/
│       ├── eks/
│       └── k8s/argo/
└── modules/                     # Reusable Terraform modules
    ├── coder/                   # Coder module
    ├── coderd/                  # Coder daemon module
    ├── network/                 # Network modules
    └── security/                # Security modules

charts/                          # Helm charts for applications
├── coder/
├── coder-provisioner/
├── cert-manager/
├── karpenter/
├── vantage/
└── ...
```

---

## Deployment Guide

### Prerequisites

- AWS Account with appropriate permissions
- Terraform >= 1.15.8
- Terragrunt >= 0.99.1
- kubectl configured for EKS access
- AWS CLI configured

### Deployment Order

1. **VPC Infrastructure**
   ```bash
   cd infra/aws/us-east-2/vpc
   terragrunt apply
   ```

2. **EKS Cluster**
   ```bash
   cd infra/aws/us-east-2/eks
   terragrunt apply
   ```

3. **RDS Database** (us-east-2 only)
   ```bash
   cd infra/aws/us-east-2/rds
   terragrunt apply
   ```

4. **ArgoCD Applications**
   
   After the EKS cluster is ready, install ArgoCD first, then deploy the application manifests:
   
   ```bash
   # Install ArgoCD
   kubectl create namespace argocd
   kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
   
   # Deploy applications via Terragrunt
   cd infra/aws/us-east-2/k8s/argo
   terragrunt run-all apply
   ```

5. **Coder Configuration**
   ```bash
   cd infra/coder
   terragrunt apply
   ```

### Environment Variables

Configuration is managed through environment variables. See `infra/coder.env` for an example configuration:

- `CODER_AWS_REGION`: AWS region
- `CODER_CLUSTER_NAME`: EKS cluster name
- `CODER_CLUSTER_VERSION`: Kubernetes version
- `CODER_VPC_CIDR`: VPC CIDR block
- Database credentials and other secrets

### Helm Charts

Custom Helm charts are located in the `charts/` directory:

- `charts/coder/`: Coder server deployment
- `charts/coder-provisioner/`: Coder workspace provisioner
- `charts/karpenter/`: Karpenter autoscaler configuration
- `charts/cert-manager/`: Certificate management
- `charts/vantage/`: Cost monitoring

Charts are deployed by ArgoCD using the Terraform-generated Application manifests.

---

## Development

### Terraform Modules

Reusable Terraform modules are located in `modules/`:

- **`modules/coder/`**: Coder-specific resources and configurations
- **`modules/coderd/`**: Coder daemon configurations
- **`modules/network/`**: VPC and networking components
- **`modules/security/`**: Security groups and IAM policies

### CI/CD

GitHub Actions workflows handle automated deployments:

- **`tf-validate.yml`**: Validates Terraform/Terragrunt syntax and formatting
- **`tf-deploy.yml`**: Applies infrastructure changes on merge to main

### Making Changes

1. Create a feature branch
2. Make your changes to infrastructure or charts
3. Run `terraform fmt` and `terragrunt hclfmt` to format code
4. Test changes in a non-production environment if possible
5. Submit a PR for review
6. After merge, changes are automatically applied via GitHub Actions

---

## Troubleshooting

### Common Issues

**ArgoCD Applications Not Syncing:**
- Verify the Application manifest was created: `kubectl get applications -n argocd`
- Check repository connectivity and credentials

**EKS Access Issues:**
- Verify IAM permissions for cluster access

**Karpenter Not Scaling:**
- Check Karpenter logs: `kubectl logs -n karpenter -l app.kubernetes.io/name=karpenter`
- Verify NodePool and EC2NodeClass configurations
- Check IAM roles and instance profiles

### Useful Commands

```bash
# Watch Karpenter logs
kubectl logs -n karpenter -l app.kubernetes.io/name=karpenter -f

# List all Terragrunt modules
cd infra && terragrunt run-all init --terragrunt-ignore-external-dependencies
```

---

## Contributing

We welcome contributions! Please:

1. Follow the existing code style and conventions
2. Test your changes thoroughly
3. Update documentation as needed
4. Submit PRs with clear descriptions

For questions or issues, reach out to `jullian@coder.com` or open a GitHub issue.
