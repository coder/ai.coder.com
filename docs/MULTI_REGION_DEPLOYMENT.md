# Multi-Region Deployment Progress

**Date:** 2025-12-02
**Status:** Pending Enterprise License

## Overview

This document tracks the progress of deploying multi-region Coder infrastructure to enable:

- **A) Automatic routing** to the nearest region based on user latency
- **B) Manual region selection** in the Coder UI for users to choose their preferred region

## Current Status

### ✅ Completed Today

#### 1. Cost Optimization - Aurora Serverless v2

- **Problem:** RDS Aurora Serverless v2 costing $130/month for both writer and reader instances
- **Solution:** Removed reader instance from `infra/aws/us-east-2/rds/main.tf`
- **Result:** Reduced cost by ~$44/month to ~$86/month (1.0 ACU total)
- **File:** `infra/aws/us-east-2/rds/main.tf`

#### 2. Cross-Region Replica Communication

- **Problem:** Coder replicas in us-east-2 and us-west-2 could detect each other but couldn't communicate (timeout errors)
- **Root Cause:** Security groups blocking port 8080 traffic between VPCs
- **Solution:**
  - Added security group rules to allow TCP port 8080 between VPC CIDRs
  - Codified rules in Terraform for reproducibility
- **Files:**
  - `infra/aws/us-east-2/vpc-peering/main.tf`
  - `infra/aws/us-east-2/vpc-peering/terraform.tfvars`

```terraform
# Security group rule to allow Coder replica communication from us-west-2 to us-east-2
resource "aws_security_group_rule" "use2_allow_coder_from_usw2" {
  provider          = aws.use2
  type              = "ingress"
  from_port         = 8080
  to_port           = 8080
  protocol          = "tcp"
  cidr_blocks       = [var.accepter_vpc_cidr]
  security_group_id = var.requester_node_security_group_id
  description       = "Allow Coder replica communication from us-west-2"
}
```

#### 3. DERP Server Configuration

- **Problem:** `/derp/latency-check` endpoint timing out, replicas couldn't sync properly
- **Root Cause:** `CODER_DERP_SERVER_ENABLE` environment variable not set
- **Solution:** Added `CODER_DERP_SERVER_ENABLE = "true"` to both regions' Coder deployments
- **Result:** Replicas now communicate successfully, no more timeout errors
- **Files:**
  - `infra/aws/us-east-2/k8s/coder-server/main.tf`
  - `infra/aws/us-west-2/k8s/coder-server/main.tf`

```terraform
env_vars = {
  CODER_REDIRECT_TO_ACCESS_URL = "false"
  CODER_TLS_ENABLE             = "false"
  CODER_SECURE_AUTH_COOKIE     = "true"
  # Enable DERP server for multi-region replica communication
  CODER_DERP_SERVER_ENABLE     = "true"
}
```

#### 4. Latency Improvement

- **Before:** 111ms
- **After:** 34ms
- Achieved through proper VPC peering, security group rules, and DERP server configuration

#### 5. Workspace Proxy Configuration (Ready for Deployment)

- Created complete Terraform configuration for us-west-2 workspace proxy
- **Files:**
  - `infra/aws/us-west-2/k8s/coder-proxy/main.tf`
  - `infra/aws/us-west-2/k8s/coder-proxy/terraform.tfvars`
  - `infra/aws/us-west-2/k8s/coder-proxy/backend.hcl`

### ⏸️ Blocked - Awaiting Enterprise License

#### Workspace Proxy Deployment

- **Problem:** "Your license is not entitled to create workspace proxies."
- **Requirement:** Coder Enterprise license required for Workspace Proxy feature
- **Impact:** Manual region selection (requirement B) cannot be completed without Enterprise license

**Error from Terraform:**

```
Error: Feature not enabled

  with module.coder-proxy.coderd_workspace_proxy.this,
  on ../../../../../modules/k8s/bootstrap/coder-proxy/main.tf line 259, in resource "coderd_workspace_proxy" "this":
 259: resource "coderd_workspace_proxy" "this" {

Your license is not entitled to create workspace proxies.
```

**Error from API:**

```json
{
  "message": "Workspace Proxy is a Premium feature. Contact sales!"
}
```

## Key Technical Concepts

### Coder Replicas vs Workspace Proxies

#### Replicas (Currently Deployed)

- **Purpose:** High availability and automatic failover
- **Behavior:** Multiple Coder instances share same database, automatic failover if one fails
- **User Experience:** Users see single "default" region, automatic routing based on DNS
- **License:** Available in all Coder editions
- **Status:** ✅ Deployed and working in us-east-2 and us-west-2

#### Workspace Proxies (Blocked by License)

- **Purpose:** User-selectable regions for manual region switching
- **Behavior:** Users can see and manually switch between regions in Coder UI
- **User Experience:** "Region" tab in UI with latency display and manual selection
- **License:** ⚠️ Requires Coder Enterprise license
- **Status:** ❌ Configuration ready but deployment blocked

## Infrastructure State

### us-east-2 (Ohio) - Primary Region

- **EKS Cluster:** `coderdemo-use2` ✅ Running
- **Coder Server:** ✅ Deployed and operational
- **Database:** Aurora Serverless v2 (1.0 ACU writer only) ✅
- **VPC CIDR:** 10.0.0.0/16
- **Node Security Group:** `<REDACTED>`
- **DERP Server:** ✅ Enabled
- **URL:** https://coderdemo.io

### us-west-2 (Oregon) - Secondary Region

- **EKS Cluster:** `coderdemo-usw2` ✅ Running
- **Coder Server:** ✅ Deployed as replica
- **Coder Proxy:** ❌ Blocked by license (configuration ready)
- **VPC CIDR:** 10.1.0.0/16
- **Node Security Group:** `<REDACTED>`
- **DERP Server:** ✅ Enabled
- **Planned URL:** https://us-west-2.coderdemo.io

### Networking

- **VPC Peering:** ✅ Established between us-east-2 and us-west-2
- **Security Group Rules:** ✅ Port 8080 allowed between regions
- **Route Tables:** ✅ Configured for cross-region routing
- **Replica Communication:** ✅ Working (34ms latency)

## Next Steps - Once Enterprise License is Obtained

### 1. Apply Enterprise License to Coder Deployment

The license needs to be applied to the primary Coder deployment at https://coderdemo.io. This is typically done through the Coder admin UI or by setting the `CODER_LICENSE` environment variable.

### 2. Deploy Workspace Proxy to us-west-2

Run from `infra/aws/us-west-2/k8s/coder-proxy`:

```bash
terraform apply -var-file=terraform.tfvars -auto-approve
```

This will:

1. Create the workspace proxy "Oregon" in Coder API
2. Deploy proxy pods to us-west-2 EKS cluster
3. Create namespace and secrets
4. Configure NLB with ACM certificate
5. Enable manual region selection in Coder UI

### 3. Verify Workspace Proxy Registration

Check that the proxy appears in Coder:

```bash
curl -H "Coder-Session-Token: <token>" https://coderdemo.io/api/v2/workspaceproxies
```

Expected response:

```json
{
  "proxies": [
    {
      "id": "...",
      "name": "us-west-2",
      "display_name": "Oregon",
      "icon": "/emojis/1f1fa-1f1f8.png",
      "url": "https://us-west-2.coderdemo.io",
      "healthy": true
    }
  ]
}
```

### 4. Configure Route53 (If Not Already Done)

Ensure latency-based routing is configured for automatic region selection:

- A record for `coderdemo.io` → us-east-2 NLB (latency-based)
- A record for `coderdemo.io` → us-west-2 NLB (latency-based)
- CNAME for `*.coderdemo.io` → coderdemo.io
- A record for `us-west-2.coderdemo.io` → us-west-2 NLB (simple routing)

### 5. Test User Experience

1. Navigate to https://coderdemo.io
2. Verify latency-based routing connects to nearest region
3. Look for "Region" selector in Coder UI
4. Click "Refresh latency" to see both regions
5. Manually select "Oregon" region
6. Verify connection switches to us-west-2

## Configuration Files

### Workspace Proxy Configuration

`infra/aws/us-west-2/k8s/coder-proxy/terraform.tfvars`:

```terraform
cluster_name    = "coderdemo-usw2"
cluster_region  = "us-west-2"
cluster_profile = "noah@coder.com"

coder_proxy_name         = "us-west-2"
coder_proxy_display_name = "Oregon"
coder_proxy_icon         = "/emojis/1f1fa-1f1f8.png"

coder_access_url          = "https://coderdemo.io"
coder_proxy_url           = "https://us-west-2.coderdemo.io"
coder_proxy_wildcard_url  = "*.us-west-2.coderdemo.io"

coder_token = "<REDACTED - See terraform.tfvars>"

addon_version = "2.27.1"
image_repo    = "ghcr.io/coder/coder"
image_tag     = "v2.27.1"

acme_registration_email      = "admin@coderdemo.io"
cloudflare_api_token         = "placeholder"
kubernetes_ssl_secret_name   = "coder-proxy-tls"
kubernetes_create_ssl_secret = false
```

### VPC Peering Configuration

`infra/aws/us-east-2/vpc-peering/terraform.tfvars`:

```terraform
profile                          = "noah@coder.com"
requester_vpc_id                 = "<REDACTED>"
accepter_vpc_id                  = "<REDACTED>"
requester_vpc_cidr               = "10.0.0.0/16"
accepter_vpc_cidr                = "10.1.0.0/16"
requester_node_security_group_id = "<REDACTED>"
accepter_node_security_group_id  = "<REDACTED>"
```

## Reference Links

- [Coder Enterprise Licensing](https://coder.com/docs/coder-oss/latest/admin/licensing)
- [Workspace Proxies Documentation](https://coder.com/docs/coder-oss/latest/admin/workspace-proxies)
- [Multi-Region Deployment Guide](https://coder.com/docs/coder-oss/latest/admin/multi-region)

## Important Notes

1. **Token Security:** The Coder API token is stored in terraform.tfvars. Consider using AWS Secrets Manager for production.

2. **S3 Backend:** All Terraform state is stored in S3 bucket in us-east-2. See backend.hcl files for configuration.

3. **Replica Communication:** Replicas use DERP protocol on port 8080 for coordination. Ensure security groups allow this traffic.

4. **DNS Propagation:** After deploying workspace proxy, DNS changes may take 5-60 minutes to propagate globally.

5. **Certificate Management:** ACM certificates are managed separately. Ensure `*.us-west-2.coderdemo.io` certificate is issued in us-west-2.

## Troubleshooting

### If Workspace Proxy Deployment Fails

1. Verify Enterprise license is applied: Check Coder admin UI → Deployment → License
2. Check Coder API token has admin permissions
3. Verify network connectivity from us-west-2 to primary deployment
4. Check pod logs: `kubectl logs -n coder-proxy -l app.kubernetes.io/name=coder`

### If Users Don't See Region Selector

1. Ensure workspace proxy status is "healthy" in API
2. Hard refresh browser (Cmd+Shift+R / Ctrl+Shift+F5)
3. Verify user has permission to see workspace proxies
4. Check Coder version supports workspace proxies (v2.0+)

## Summary

**What Works Now:**

- ✅ Multi-region Coder replicas (us-east-2, us-west-2)
- ✅ Automatic failover between replicas
- ✅ Cross-region communication via DERP
- ✅ 34ms inter-region latency
- ✅ Cost-optimized Aurora database

**What's Pending:**

- ⏸️ Manual region selection in UI (blocked by Enterprise license)
- ⏸️ Workspace proxy deployment (configuration ready)

**Action Required:**

1. Obtain Coder Enterprise license
2. Apply license to deployment
3. Run `terraform apply` for workspace proxy
4. Verify region selector appears in UI
