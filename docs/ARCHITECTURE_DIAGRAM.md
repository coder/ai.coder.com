# Coder Demo Environment Architecture Diagram

This document provides a comprehensive visual representation of the **coderdemo.io** infrastructure architecture.

---

## Table of Contents

1. [Overview Diagram](#overview-diagram)
2. [Component Details](#component-details)
3. [Traffic Flow](#traffic-flow)
4. [Key Architecture Decisions](#key-architecture-decisions)

---

## Overview Diagram

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              INTERNET / USERS                                │
└─────────────────────────────────────────────────────────────────────────────┘
                                      │
                                      │ HTTPS
                                      ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                         AWS ROUTE 53 (coderdemo.io)                          │
│                                                                               │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │ LATENCY-BASED ROUTING (Automatic)                                    │   │
│  │  • coderdemo.io          → Nearest region (health check monitored)   │   │
│  │  • *.coderdemo.io        → Workspace apps (latency-routed)           │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                               │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │ REGION-SPECIFIC ROUTING (Manual Override)                            │   │
│  │  • us-east-2.coderdemo.io      → Force Ohio region                   │   │
│  │  • us-west-2.coderdemo.io      → Force Oregon region                 │   │
│  │  • *.us-east-2.coderdemo.io    → Ohio workspace apps                 │   │
│  │  • *.us-west-2.coderdemo.io    → Oregon workspace apps               │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────┘
              │                                              │
              │                                              │
    ┌─────────▼──────────┐                       ┌──────────▼─────────┐
    │  US-EAST-2 (Ohio)  │                       │ US-WEST-2 (Oregon) │
    │   PRIMARY REGION   │                       │  SECONDARY REGION  │
    └────────────────────┘                       └────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────┐
│                          US-EAST-2 REGION (PRIMARY)                          │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                               │
│  ┌────────────────────────────────────────────────────────────────────┐    │
│  │                    NETWORK LOAD BALANCER (NLB)                      │    │
│  │  • TLS Termination (ACM Certificate)                                │    │
│  │  • Static IP Addresses (per AZ)                                     │    │
│  │  • Layer 4 (TCP) - Low latency                                      │    │
│  │  • Source IP Preservation                                           │    │
│  │  • HTTPS:443 → HTTP:8080 (backend)                                  │    │
│  └────────────────────────────────────────────────────────────────────┘    │
│                                  │                                           │
│  ┌───────────────────────────────▼──────────────────────────────────┐      │
│  │                         VPC (10.0.0.0/16)                          │      │
│  │                                                                     │      │
│  │  ┌─────────────────────────────────────────────────────────┐     │      │
│  │  │                  PUBLIC SUBNETS (system0, system1)       │     │      │
│  │  │  • Internet Gateway (IGW)                                │     │      │
│  │  │  • NAT Gateway (fck-nat - cost optimized)                │     │      │
│  │  │  • Network Load Balancers                                │     │      │
│  │  │  • Multi-AZ (us-east-2a, us-east-2b)                     │     │      │
│  │  └─────────────────────────────────────────────────────────┘     │      │
│  │                              │                                     │      │
│  │  ┌───────────────────────────▼─────────────────────────────┐     │      │
│  │  │                  PRIVATE SUBNETS                          │     │      │
│  │  │                                                            │     │      │
│  │  │  ┌──────────────────────────────────────────────────┐   │     │      │
│  │  │  │ SYSTEM SUBNETS (system0, system1)                │   │     │      │
│  │  │  │  • EKS Control Plane                              │   │     │      │
│  │  │  │  • EKS Managed Node Groups                        │   │     │      │
│  │  │  │  • Graviton ARM instances (t4g.xlarge)            │   │     │      │
│  │  │  │  • ON_DEMAND capacity (stable)                    │   │     │      │
│  │  │  └──────────────────────────────────────────────────┘   │     │      │
│  │  │                                                            │     │      │
│  │  │  ┌──────────────────────────────────────────────────┐   │     │      │
│  │  │  │ PROVISIONER SUBNET                                │   │     │      │
│  │  │  │  • Coder External Provisioner pods                │   │     │      │
│  │  │  │  • Workspace orchestration                        │   │     │      │
│  │  │  └──────────────────────────────────────────────────┘   │     │      │
│  │  │                                                            │     │      │
│  │  │  ┌──────────────────────────────────────────────────┐   │     │      │
│  │  │  │ WORKSPACE SUBNET (ws-all)                         │   │     │      │
│  │  │  │  • Coder Workspace pods                           │   │     │      │
│  │  │  │  • Karpenter auto-scaled nodes                    │   │     │      │
│  │  │  │  • User development environments                  │   │     │      │
│  │  │  └──────────────────────────────────────────────────┘   │     │      │
│  │  │                                                            │     │      │
│  │  │  ┌──────────────────────────────────────────────────┐   │     │      │
│  │  │  │ RDS SUBNET (Database)                             │   │     │      │
│  │  │  │  • Aurora PostgreSQL 15.8 (Serverless v2)         │   │     │      │
│  │  │  │  • Auto-scaling: 0.5-16 ACU (1-32 GB RAM)         │   │     │      │
│  │  │  │  • Multi-AZ: Writer + Reader instances            │   │     │      │
│  │  │  │  • Private only (no public access)                │   │     │      │
│  │  │  │  • Shared across regions                          │   │     │      │
│  │  │  └──────────────────────────────────────────────────┘   │     │      │
│  │  │                                                            │     │      │
│  │  │  ┌──────────────────────────────────────────────────┐   │     │      │
│  │  │  │ VPC ENDPOINTS (Cost Optimization)                 │   │     │      │
│  │  │  │  • S3 Gateway Endpoint                            │   │     │      │
│  │  │  │  • ECR API Interface Endpoint                     │   │     │      │
│  │  │  │  • ECR DKR Interface Endpoint                     │   │     │      │
│  │  │  │  • Reduces NAT Gateway data transfer costs        │   │     │      │
│  │  │  └──────────────────────────────────────────────────┘   │     │      │
│  │  └────────────────────────────────────────────────────────┘     │      │
│  └─────────────────────────────────────────────────────────────────┘      │
│                                                                               │
│  ┌────────────────────────────────────────────────────────────────────┐    │
│  │                   EKS CLUSTER (Kubernetes 1.x)                      │    │
│  │                                                                      │    │
│  │  ┌──────────────────────────────────────────────────────────┐     │    │
│  │  │ CODER NAMESPACE                                           │     │    │
│  │  │  • Coder Server (Deployment)                              │     │    │
│  │  │    - CODER_TLS_ENABLE = false (NLB handles TLS)           │     │    │
│  │  │    - CODER_SECURE_AUTH_COOKIE = true                      │     │    │
│  │  │    - CODER_REDIRECT_TO_ACCESS_URL = false                 │     │    │
│  │  │    - GitHub OAuth integration                             │     │    │
│  │  │    - PostgreSQL RDS connection                            │     │    │
│  │  │  • Service Type: LoadBalancer (creates NLB)               │     │    │
│  │  │  • ACM Certificate for TLS termination                    │     │    │
│  │  └──────────────────────────────────────────────────────────┘     │    │
│  │                                                                      │    │
│  │  ┌──────────────────────────────────────────────────────────┐     │    │
│  │  │ CODER-WS NAMESPACE (Workspaces)                           │     │    │
│  │  │  • Coder External Provisioner (Deployment)                │     │    │
│  │  │  • Workspace pods (dynamically created)                   │     │    │
│  │  │  • EBS volumes for persistent storage                     │     │    │
│  │  │  • IRSA for AWS permissions                               │     │    │
│  │  └──────────────────────────────────────────────────────────┘     │    │
│  │                                                                      │    │
│  │  ┌──────────────────────────────────────────────────────────┐     │    │
│  │  │ INFRASTRUCTURE SERVICES (kube-system, etc.)               │     │    │
│  │  │  • AWS Load Balancer Controller                           │     │    │
│  │  │    - Creates and manages NLBs                             │     │    │
│  │  │    - Service annotations for TLS termination              │     │    │
│  │  │  • Karpenter                                               │     │    │
│  │  │    - Auto-scaling for workspace nodes                     │     │    │
│  │  │    - SQS queue + EventBridge                              │     │    │
│  │  │    - Cost-optimized instance selection                    │     │    │
│  │  │  • EBS CSI Driver                                          │     │    │
│  │  │    - Dynamic volume provisioning                          │     │    │
│  │  │  • Cert-Manager                                            │     │    │
│  │  │    - Certificate management                               │     │    │
│  │  │  • Metrics Server                                          │     │    │
│  │  │    - Resource metrics collection                          │     │    │
│  │  │  • CoreDNS, kube-proxy, vpc-cni (EKS addons)              │     │    │
│  │  └──────────────────────────────────────────────────────────┘     │    │
│  └────────────────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────┐
│                          US-WEST-2 REGION (SECONDARY)                        │
├─────────────────────────────────────────────────────────────────────────────┤
│  • Similar architecture to us-east-2                                         │
│  • Infrastructure code exists (acm/, k8s/coder-server/, route53/)            │
│  • NOT YET DEPLOYED (pending deployment)                                     │
│  • Would share the same RDS database for unified accounts                    │
│  • Independent EKS cluster with own NLB                                      │
└─────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────┐
│                               SECURITY LAYER                                 │
├─────────────────────────────────────────────────────────────────────────────┤
│  • IAM Roles (IRSA - IAM Roles for Service Accounts)                        │
│    - Coder Server → RDS access                                              │
│    - Coder Provisioner → EC2/EKS permissions                                │
│    - EBS Controller → EBS volume management                                 │
│    - Load Balancer Controller → ELB management                              │
│    - Karpenter → EC2 instance launching                                     │
│  • Security Groups                                                           │
│    - EKS cluster security group                                              │
│    - Node security group                                                     │
│    - RDS security group (port 5432 from VPC CIDR)                           │
│    - VPC endpoints security group (port 443)                                │
│  • Network ACLs                                                              │
│  • TLS Certificates (ACM)                                                    │
│    - Auto-renewal enabled                                                    │
│    - Dynamically fetched (not hardcoded)                                    │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Component Details

### DNS Layer (Route 53)

**Hosted Zone:** `coderdemo.io`

**Routing Policies:**

1. **Latency-Based Routing (Primary)**
   - Automatically routes users to the nearest AWS region
   - Health checks monitor regional availability
   - Automatic failover if a region becomes unhealthy
   - Records: `coderdemo.io` and `*.coderdemo.io`

2. **Region-Specific Routing (Manual Override)**
   - Allows explicit region selection
   - Useful for demos, testing, and regional preferences
   - Records:
     - `us-east-2.coderdemo.io` (Ohio)
     - `us-west-2.coderdemo.io` (Oregon)
     - Wildcards for workspace apps

### Network Architecture

**VPC Configuration:**

- CIDR Block: `10.0.0.0/16`
- Multi-AZ deployment (2 availability zones per region)

**Subnet Types:**

1. **Public Subnets** (`system0`, `system1`)
   - Internet Gateway for outbound internet access
   - NAT Gateway (fck-nat for cost optimization)
   - Network Load Balancers
   - CIDR: `10.0.10.0/24`, `10.0.11.0/24`

2. **Private Subnets**
   - **System Subnets** (`system0`, `system1`)
     - EKS managed node groups
     - Core infrastructure services
     - CIDR: `10.0.20.0/24`, `10.0.21.0/24`

   - **Provisioner Subnet**
     - Coder external provisioner pods
     - Workspace orchestration
     - CIDR: `10.0.22.0/24`

   - **Workspace Subnet** (`ws-all`)
     - User workspace pods
     - Karpenter-managed nodes
     - CIDR: `10.0.16.0/22` (larger range for scalability)

   - **RDS Subnet**
     - PostgreSQL database
     - Multi-AZ for high availability
     - No public access

**VPC Endpoints (Cost Optimization):**

- S3 Gateway Endpoint
- ECR API Interface Endpoint
- ECR DKR Interface Endpoint
- Reduces NAT Gateway data transfer costs

### Load Balancing

**Network Load Balancer (NLB):**

- **Type:** Layer 4 (TCP/TLS)
- **TLS Termination:** Yes (via ACM certificates)
- **Benefits:**
  - Low latency for WebSocket connections
  - Source IP preservation for audit logs
  - Static IP addresses per availability zone
  - Better for long-lived connections
- **Configuration:**
  - Listener: HTTPS:443 → HTTP:8080 (Coder backend)
  - Health checks enabled
  - Cross-zone load balancing enabled

### Compute Layer

**EKS Cluster:**

- Kubernetes version: Latest stable
- Control plane: Fully managed by AWS
- Public and private endpoint access enabled

**Node Groups:**

1. **System Managed Node Group**
   - Instance type: `t4g.xlarge` (Graviton ARM)
   - Capacity: ON_DEMAND (stable, no interruptions)
   - Auto-scaling: 0-10 nodes
   - Volume: 20GB gp3 (cost-optimized)
   - Purpose: Core Kubernetes services

2. **Workspace Nodes (Karpenter-managed)**
   - Dynamic provisioning based on workspace requirements
   - Cost-optimized instance selection
   - Automatic scaling and termination
   - Spot instances supported for cost savings

**Karpenter Configuration:**

- SQS queue for event handling
- EventBridge for EC2 spot interruption notifications
- IAM role for instance launching
- Custom node classes for different workspace types

### Storage Layer

**Aurora Serverless v2 (PostgreSQL):**

- Engine: Aurora PostgreSQL 15.8
- Instance class: `db.serverless` (auto-scaling)
- Scaling: 0.5-16 ACU (Coder), 0.5-8 ACU (LiteLLM)
- Multi-AZ: Writer + Reader instances
- Encryption: At rest and in transit
- Backup: Automated daily backups (7-day retention)
- Access: Private only (from VPC CIDR)
- Cost: Pay-per-ACU-hour (~$9-$400/month depending on load)

**Amazon EBS:**

- CSI Driver: Installed via Helm
- Volume type: gp3 (general purpose SSD)
- Dynamic provisioning for workspace persistent storage
- Encryption: Enabled

### Kubernetes Services

**Core Services:**

1. **Coder Server** (Namespace: `coder`)
   - Deployment with multiple replicas
   - Service type: LoadBalancer (creates NLB)
   - Environment variables:
     - `CODER_TLS_ENABLE=false` (NLB handles TLS)
     - `CODER_SECURE_AUTH_COOKIE=true`
     - `CODER_REDIRECT_TO_ACCESS_URL=false`
   - Connected to PostgreSQL RDS
   - GitHub OAuth integration

2. **Coder External Provisioner** (Namespace: `coder-ws`)
   - Manages workspace lifecycle
   - Creates and destroys workspace pods
   - IRSA for AWS permissions

3. **AWS Load Balancer Controller**
   - Reconciles Kubernetes Service resources
   - Creates and manages NLBs
   - Handles TLS certificate attachment
   - Service annotations for configuration

4. **Karpenter**
   - Node auto-scaling
   - Instance type selection
   - Spot instance management
   - Cost optimization

5. **EBS CSI Driver**
   - Dynamic volume provisioning
   - Volume snapshots
   - Volume resizing

6. **Cert-Manager**
   - SSL/TLS certificate management
   - Automatic renewal
   - Integration with Let's Encrypt or ACM

7. **Metrics Server**
   - Resource metrics collection
   - HPA (Horizontal Pod Autoscaler) support

**EKS Addons:**

- CoreDNS (DNS resolution)
- kube-proxy (network proxy)
- vpc-cni (VPC networking)

### Security

**IAM Roles (IRSA):**

- Coder Server: RDS access, Secrets Manager
- Coder Provisioner: EC2, EKS permissions
- EBS Controller: EBS volume operations
- Load Balancer Controller: ELB operations
- Karpenter: EC2 instance launching

**Security Groups:**

- EKS cluster security group
- Node security group
- RDS security group (port 5432 from VPC)
- VPC endpoints security group (port 443)

**TLS Certificates:**

- Managed by ACM
- Automatic renewal
- Attached to NLB via Load Balancer Controller

---

## Traffic Flow

### User Authentication Flow

```
User Browser
    │
    │ HTTPS
    ▼
Route 53 (coderdemo.io)
    │
    │ Latency-based routing
    ▼
Network Load Balancer (TLS termination)
    │
    │ HTTP:8080
    ▼
Coder Server Pod
    │
    ├──→ GitHub OAuth (authentication)
    │
    └──→ PostgreSQL RDS (user data)
```

### Workspace Creation Flow

```
User (via Coder UI)
    │
    ▼
Coder Server
    │
    │ Creates workspace resource
    ▼
Coder External Provisioner
    │
    ├──→ Checks node capacity
    │
    ├──→ Karpenter provisions new node (if needed)
    │     │
    │     └──→ EC2 API (launches instance)
    │
    ├──→ Schedules workspace pod on node
    │
    ├──→ EBS CSI creates persistent volume
    │
    └──→ Workspace pod starts
          │
          └──→ User can access workspace
```

### Workspace Application Access Flow

```
User Browser
    │
    │ HTTPS (workspace-123.coderdemo.io)
    ▼
Route 53 (*.coderdemo.io wildcard)
    │
    │ Latency-based routing
    ▼
Network Load Balancer
    │
    │ HTTP
    ▼
Coder Server (proxy)
    │
    │ Proxies to workspace
    ▼
Workspace Pod (port 8000, 3000, etc.)
```

---

## Key Architecture Decisions

### 1. Network Load Balancer (NLB) over Application Load Balancer (ALB)

**Why NLB:**

- **Lower latency:** Layer 4 (TCP) vs Layer 7 (HTTP)
- **Source IP preservation:** Essential for Coder audit logs
- **Static IPs:** Easier for enterprise firewall rules
- **Long-lived connections:** Better for WebSocket connections (terminals, live updates)
- **Cost efficiency:** Lower cost at high volume

**TLS Termination at NLB:**

- NLBs DO support TLS termination when configured with ACM certificates
- Configured via AWS Load Balancer Controller service annotations
- Traffic flow: User (HTTPS:443) → NLB (terminates TLS) → Coder (HTTP:8080)

### 2. Multi-Region with Latency-Based Routing

**Benefits:**

- **Automatic performance optimization:** Users connect to nearest region
- **Built-in failover:** Route53 health checks automatically remove unhealthy regions
- **Manual override available:** Region-specific URLs for demos and testing
- **Global reach:** Serves users worldwide with low latency

**Implementation:**

- Route53 latency routing policy
- Health checks per region
- Shared RDS database across regions (for unified accounts)

### 3. Cost Optimizations

**Implemented:**

- **Graviton ARM instances:** t4g.xlarge (lower cost than x86)
- **VPC Endpoints:** S3, ECR API/DKR (reduces NAT Gateway costs)
- **fck-nat:** Custom NAT solution instead of AWS NAT Gateway
- **Karpenter:** Right-sized workspace nodes, automatic termination
- **gp3 volumes:** Better performance than gp2 at same cost
- **Spot instances:** For workspace nodes (when interruption-tolerant)

### 4. Security Best Practices

**IRSA (IAM Roles for Service Accounts):**

- No AWS credentials stored in Kubernetes secrets
- Least-privilege access per service
- Automatic credential rotation

**Network Segmentation:**

- Separate subnets for system, provisioner, and workspaces
- RDS in private subnet with no public access
- Security groups restrict traffic by source/destination

**TLS Everywhere:**

- ACM certificates with auto-renewal
- TLS termination at load balancer
- Secure cookies enabled

### 5. Helm Chart Management

**Decision: `upgrade_install = true`**

- Idempotent Terraform applies
- No "already exists" errors in CI/CD
- Declarative version management
- Re-added in Helm provider version 3.1.1

### 6. Aurora Serverless v2 for Cost Optimization

**Configuration:**

- Engine: Aurora PostgreSQL 15.8 (Serverless v2)
- Scaling: 0.5-16 ACU for Coder, 0.5-8 ACU for LiteLLM
- Multi-AZ: Writer + Reader instances

**Benefits:**

- **Cost savings:** Scales down to 0.5 ACU (~$9/month) during idle periods
- **Auto-scaling:** Automatically scales up to handle load (up to 16 ACU = 32 GB RAM)
- **No manual intervention:** Seamless scaling based on demand
- **Pay-per-use:** Only pay for ACU-hours consumed vs 24/7 provisioned instance

**Trade-off:**

- **Cold start delay:** 5-10 second initial response after idle period (>30 minutes)
- **Acceptable for demo environment** where cost optimization outweighs instant response

---

## Known Behaviors (Demo Environment)

This section documents expected behaviors in the demo environment that optimize for cost over instant response time.

### 1. Aurora Serverless v2 Cold Start (5-10 seconds)

**When it happens:**

- After 30+ minutes of no database activity
- First visitor after idle period

**What you'll see:**

- Site takes 5-10 seconds to load initially
- Subsequent requests are instant (<100ms)
- Aurora scales from 0.5 ACU → 1-2 ACU automatically

**Why it's acceptable:**

- Demo environment prioritizes cost savings
- Saves ~$120/month vs provisioned RDS
- No errors, just slower initial load
- Perfect for sporadic demo usage

**To eliminate (if needed):**

- Increase `min_capacity = 2` in `infra/aws/us-east-2/rds/main.tf`
- Trade-off: ~$35/month baseline vs $9/month

### 2. HTTP→HTTPS Redirect Delay ("Not Secure" Warning)

**When it happens:**

- User types `coderdemo.io` without `https://`
- Browser tries HTTP:80 first (standard behavior)

**What you'll see:**

1. Browser shows "Connecting..." or spinning
2. Brief "Site is not secure" warning (2-3 seconds)
3. Warning disappears, site loads normally with HTTPS

**Root cause:**

- NLB only has port 443 (HTTPS) listener configured
- No port 80 (HTTP) listener to redirect to HTTPS
- NLBs don't support HTTP→HTTPS redirects (ALB feature only)
- Browser timeout on port 80, then retries port 443

**Why it's acceptable:**

- Demo environment, not production
- Site works perfectly once HTTPS connects
- No security risk (just UX delay)
- Users who bookmark or click links use HTTPS directly

**Workarounds:**

- Always share URLs as `https://coderdemo.io`
- Bookmark uses HTTPS automatically
- Browser remembers HTTPS after first visit

**To eliminate (if needed):**

- Option A: Add CloudFront with HTTP→HTTPS redirect
- Option B: Switch to ALB (loses NLB benefits)
- Option C: Configure port 80 forwarding in Coder service

### Summary of Expected Load Times

| Scenario                  | Load Time       | Behavior                                           |
| ------------------------- | --------------- | -------------------------------------------------- |
| **First visit (HTTP)**    | 7-13 seconds    | HTTP:80 timeout (2-3s) + Aurora cold start (5-10s) |
| **First visit (HTTPS)**   | 5-10 seconds    | Aurora cold start only                             |
| **After warm-up**         | <100ms          | Instant, everything cached                         |
| **Bookmarked/HTTPS link** | <100ms or 5-10s | Instant if warm, cold start if idle                |

---

## Infrastructure as Code

All infrastructure is managed via Terraform:

**Directory Structure:**

```
infra/aws/
├── us-east-2/          # Primary region (deployed)
│   ├── eks/            # EKS cluster
│   ├── rds/            # PostgreSQL database
│   ├── route53/        # DNS records
│   └── k8s/            # Kubernetes applications
│       ├── coder-server/
│       ├── karpenter/
│       ├── lb-controller/
│       └── ...
├── us-west-2/          # Secondary region (code exists, not deployed)
│   ├── acm/
│   ├── eks/
│   ├── route53/
│   └── k8s/
└── eu-west-2/          # Tertiary region (partial code)

modules/
├── compute/
│   └── cluster/        # Reusable EKS cluster module
├── network/
│   └── eks-vpc/        # Reusable VPC module
└── k8s/
    └── bootstrap/      # Reusable K8s app modules
```

**Terraform State:**

- Stored in S3 backend
- State locking via DynamoDB
- Separate state files per region/component

---

## Deployment Status

### US-EAST-2 (Ohio) - PRIMARY

✅ **DEPLOYED**

- EKS cluster
- RDS PostgreSQL
- Route53 DNS records
- All Kubernetes services
- Coder server operational

### US-WEST-2 (Oregon) - SECONDARY

⏳ **PENDING DEPLOYMENT**

- Infrastructure code exists
- ACM certificates ready to deploy
- Coder server configuration ready
- Route53 DNS records ready
- Needs deployment to become active

### EU-WEST-2 (London) - TERTIARY

🚧 **PARTIAL CODE**

- Some infrastructure modules present
- Not fully configured

---

## Monitoring and Observability

**Currently Configured:**

- Route53 health checks
- EKS control plane logs
- Kubernetes metrics server
- Load balancer metrics (CloudWatch)

**Recommended Additions:**

- Prometheus for metrics collection
- Grafana for visualization
- AWS X-Ray for distributed tracing
- CloudWatch Container Insights
- Coder audit logs to CloudWatch/S3

---

## Disaster Recovery

**Current Strategy:**

- Multi-AZ RDS deployment (automatic failover)
- Multi-region infrastructure code (can deploy us-west-2 rapidly)
- Route53 health checks and automatic failover
- Automated daily RDS backups

**RTO/RPO:**

- **RTO (Recovery Time Objective):** ~20 minutes (deploy us-west-2)
- **RPO (Recovery Point Objective):** <1 minute (RDS Multi-AZ synchronous replication)

---

## Scaling Considerations

**Horizontal Scaling:**

- Coder server: Increase replica count in Helm values
- Workspace nodes: Karpenter automatically scales based on demand
- System nodes: Adjust EKS managed node group size

**Vertical Scaling:**

- RDS: Change instance class (requires downtime or blue/green deployment)
- Workspace resources: Update Coder template resource requests/limits
- Node instance types: Modify Karpenter NodePool configuration

**Regional Expansion:**

- Deploy us-west-2 for West Coast users
- Deploy eu-west-2 for European users
- Consider VPC peering or Transit Gateway for inter-region communication

---

## Related Documentation

- [Infrastructure Best Practices](./INFRASTRUCTURE_BEST_PRACTICES.md)
- [README](../README.md)

---

## Changelog

- **2025-11-26**: Updated to reflect Aurora Serverless v2 configuration; added "Known Behaviors" section documenting cold start and HTTP redirect behavior for demo environment
- **2025-11-25**: Initial architecture diagram created

---

## Questions or Feedback

For technical questions about this architecture, contact the infrastructure team.
