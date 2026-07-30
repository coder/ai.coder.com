# AI Demo Environment (ai.coder.com)

Welcome to the AI Demo Environment's GitHub repository! 

This project powers [ai.coder.com](https://ai.coder.com), allowing users to experiment with the latest AI features in Coder.

---

## Getting Started

> [!IMPORTANT] Before accessing the deployment, make sure you've been invited to the "coder-contrib" GitHub organization. If not, reach out to `jullian@coder.com` with your GitHub handle.

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
- AWS SSO configured for Grafana access
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

### Helm Charts

Custom Helm charts are located in the `charts/` directory:

- `charts/coder/`: Coder server deployment
- `charts/coder-provisioner/`: Coder workspace provisioner
- `charts/karpenter/`: Karpenter autoscaler configuration
- `charts/cert-manager/`: Certificate management
- `charts/vantage/`: Cost monitoring

Charts are deployed by ArgoCD using the Terraform-generated Application manifests.

---

## Monitoring and Observability

### Overview

The us-east-2 deployment includes a comprehensive monitoring stack built on AWS Managed Grafana, CloudWatch, and Prometheus. This provides full visibility into the Coder deployment, Kubernetes cluster health, and application performance.

### Architecture

**AWS Managed Grafana**
- Deployed in VPC with private subnets for security
- Integrated with AWS SSO for authentication
- Organizational unit access for Root, Coder, and Customer OUs
- Service account with rotating tokens (30-day rotation)
- Grafana version 10.4

**Data Sources**
- **Amazon Managed Service for Prometheus (AMP)**: Fully managed Prometheus service for metrics storage and querying (no in-cluster Prometheus pods)
- **CloudWatch**: AWS service metrics and logs
- **Grafana Agent**: In-cluster metrics and logs collection, sends to AMP
- **Loki** (optional): Log aggregation
- **PostgreSQL Exporter**: Database metrics

**Exporters and Collectors**
- **Kube State Metrics**: Kubernetes object state metrics
- **Node Exporter**: Host-level metrics (CPU, memory, disk, network)
- **PostgreSQL Exporter**: RDS database performance metrics
- **Grafana Agent**: Unified observability agent in DaemonSet mode
- **AWS for Fluent Bit**: Log forwarding to CloudWatch

### Dashboards

The deployment includes pre-configured Grafana dashboards for comprehensive monitoring:

**Coder-Specific Dashboards:**
1. **Status Dashboard** (`status.json`)
   - Overall system health
   - Component availability (coderd, provisioners, workspaces)
   - Service status and uptime

2. **Coderd Dashboard** (`coderd.json`)
   - Coder server performance metrics
   - API request rates and latency
   - Active connections and sessions
   - Resource utilization

3. **Provisioner Dashboard** (`provisionerd.json`)
   - Provisioner job queue depth
   - Job execution times
   - Success/failure rates
   - Resource allocation

4. **Workspaces Dashboard** (`workspaces.json`)
   - Aggregate workspace metrics
   - Build times and success rates
   - Active workspace count
   - Resource consumption by workspace

5. **Workspace Detail Dashboard** (`workspace_detail.json`)
   - Individual workspace performance
   - Per-workspace resource usage
   - Container metrics
   - Network I/O

6. **Prebuilds Dashboard** (`prebuilds.json`)
   - Template prebuild status
   - Build duration trends
   - Cache hit rates

**Additional Dashboards:**
- **AI Bridge Dashboard** (`aibridge.json`): AI provider integration metrics
- **Boundary Dashboard** (`boundary.json`): Network boundary metrics

### Metrics Collection

**Amazon Managed Service for Prometheus (AMP):**
- Fully managed Prometheus-compatible service
- No in-cluster Prometheus server deployment required
- Grafana Agent scrapes metrics and remote writes to AMP
- Long-term metrics storage and querying
- Automatic scaling and high availability

**Metrics Sources:**
- Coder application metrics (via `/metrics` endpoint on port 2112)
- Kubernetes cluster metrics (via kube-state-metrics)
- Container resource utilization (via node-exporter)
- PostgreSQL database metrics (via postgres-exporter)
- Custom application metrics

**CloudWatch Integration:**
- EKS control plane logs
- RDS database metrics
- VPC flow logs
- AWS Load Balancer metrics
- Lambda function metrics (if applicable)

**Log Aggregation:**
- Application logs via Fluent Bit
- Kubernetes audit logs
- Container stdout/stderr
- System logs from EC2 nodes

### Monitoring Infrastructure

**Grafana Workspace Configuration:**
```hcl
# IAM Role with permissions for:
# - Amazon Managed Service for Prometheus (AMP)
# - CloudWatch access
# - VPC deployment in private subnets

# Data sources: PROMETHEUS, CLOUDWATCH
# Authentication: AWS SSO
# Permission type: CUSTOMER_MANAGED
```

**Coder Observability Helm Chart:**

The `coder-observability` chart deploys a complete monitoring stack with configurable components:

- **kube-state-metrics**: Kubernetes object metrics
- **prometheus-node-exporter**: Node-level metrics
- **prometheus-postgres-exporter**: PostgreSQL metrics with External Secrets integration
- **grafana-agent**: Unified metrics and logs collection (DaemonSet)
- **loki**: Log aggregation (optional)

All components support custom affinity rules and tolerations for node placement.

### Selectors and Filtering

Dashboards use PromQL selectors to filter metrics by component:

- **Coderd**: `pod=~'coder.*', namespace=~'coder'`
- **Provisioners**: `pod=~'coder-provisioner.*', namespace=~'(coder-ws|coder-ws-experiment|coder-ws-demo)'`
- **Workspaces**: `pod!~'coder.*', namespace=~'(coder-ws|coder-ws-experiment|coder-ws-demo)'`

### Accessing Grafana

1. Navigate to AWS Managed Grafana workspace in AWS Console
2. Click "Grafana workspace URL"
3. Authenticate with AWS SSO
4. Dashboards are pre-configured in the "Coder" folder

### Alerting

CloudWatch alarms can be configured for:
- High CPU/memory utilization
- RDS connection exhaustion
- API error rates
- Workspace build failures
- Disk space usage

Configure alerts through AWS CloudWatch or Grafana alerting rules.

### Cost Monitoring

**Vantage Integration:**
- Deployed via ArgoCD in both regions
- Tracks AWS resource costs
- Reports on Coder-specific spending
- Kubernetes cost allocation

**Key Metrics:**
- Per-workspace compute costs
- Storage costs (EBS volumes, RDS)
- Network transfer costs
- Regional cost breakdown

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
# Access AWS Managed Grafana
aws grafana list-workspaces --region us-east-2

# Get Grafana workspace URL
aws grafana describe-workspace --workspace-id <workspace-id> --region us-east-2 --query 'workspace.endpoint' --output text

# Watch Karpenter logs
kubectl logs -n karpenter -l app.kubernetes.io/name=karpenter -f

# Check Grafana Agent status
kubectl get pods -n coder-observability -l app.kubernetes.io/name=grafana-agent

# View Coder metrics endpoint
kubectl port-forward -n coder <coder-pod> 2112:2112
curl http://localhost:2112/metrics

# Check monitoring stack health (exporters and agents only)
kubectl get pods -n coder-observability

# Check Grafana Agent configuration
kubectl describe cm -n coder-observability grafana-agent

# View metrics being collected by Grafana Agent
kubectl logs -n coder-observability -l app.kubernetes.io/name=grafana-agent --tail=100

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
