# Pre-Workshop Validation Checklist

**Workshop Date**: **\*\*\*\***\_**\*\*\*\***  
**Expected Participants**: **\*\*\*\***\_**\*\*\*\***  
**Validated By**: **\*\*\*\***\_**\*\*\*\***  
**Validation Date**: **\*\*\*\***\_**\*\*\*\***

## Purpose

This checklist ensures all systems are operational and properly configured before each monthly workshop. Complete this checklist **2 days before** the workshop.

---

## 1. Authentication & Access

### LiteLLM Keys

- [ ] **Check AWS Bedrock credentials expiration**:

  ```bash
  # Check AWS IAM role credentials used by LiteLLM
  kubectl get secret litellm-aws-credentials -n litellm -o jsonpath='{.data}' | base64 -d

  # Verify AWS Bedrock access
  kubectl exec -n litellm deploy/litellm -- curl -X GET https://bedrock-runtime.us-east-1.amazonaws.com/
  ```

- [ ] **Check GCP Vertex credentials expiration**:
  ```bash
  # Check GCP service account key expiration
  kubectl get secret litellm-gcp-credentials -n litellm -o jsonpath='{.data}' | base64 -d
  ```
- [ ] **Verify auxiliary addon key rotation schedule**: Keys rotate every 4-5 hours
  - [ ] **Action Required**: Ensure rotation will NOT occur during workshop window
  - [ ] **Note**: Key rotation forces all workspaces to restart
- [ ] **Result**: AWS credentials expire on: **\*\*\*\***\_**\*\*\*\***
- [ ] **Result**: GCP credentials expire on: **\*\*\*\***\_**\*\*\*\***
- [ ] **Action Required**: If <7 days, rotate keys using documented procedure

### GitHub OAuth

- [ ] **Test GitHub authentication** for internal users (Okta flow)
- [ ] **Test GitHub authentication** for external users (GitHub direct)
- [ ] **Verify coder-contrib org access** for test external account

---

## 2. Multi-Region Infrastructure

### Image Consistency

**Expected Image**: `ghcr.io/coder/coder-preview` (mirrored to private ECR)

- [ ] **Control Plane (us-east-2)** - Verify Coder Server image version:

  ```bash
  kubectl get pods -n coder -o jsonpath='{.items[*].spec.containers[*].image}' --context=us-east-2
  ```

  - Image: **\*\*\*\***\_**\*\*\*\***
  - Tag/Digest: **\*\*\*\***\_**\*\*\*\***

- [ ] **Oregon Proxy (us-west-2)** - Verify Coder Proxy image version:

  ```bash
  kubectl get pods -n coder -o jsonpath='{.items[*].spec.containers[*].image}' --context=us-west-2
  ```

  - Image: **\*\*\*\***\_**\*\*\*\***
  - Tag/Digest: **\*\*\*\***\_**\*\*\*\***

- [ ] **London Proxy (eu-west-2)** - Verify Coder Proxy image version:

  ```bash
  kubectl get pods -n coder -o jsonpath='{.items[*].spec.containers[*].image}' --context=eu-west-2
  ```

  - Image: **\*\*\*\***\_**\*\*\*\***
  - Tag/Digest: **\*\*\*\***\_**\*\*\*\***

- [ ] **Verify private ECR mirror** is up-to-date with latest `ghcr.io/coder/coder-preview`:

  ```bash
  # Get latest digest from GitHub Container Registry
  crane digest ghcr.io/coder/coder-preview:latest

  # Get digest from private ECR
  aws ecr describe-images --repository-name coder-preview --region us-east-2 --query 'sort_by(imageDetails,& imagePushedAt)[-1].imageDigest'
  ```

  - GHCR Digest: **\*\*\*\***\_**\*\*\*\***
  - ECR Digest: **\*\*\*\***\_**\*\*\*\***

- [ ] **Confirm all clusters use identical images and digests**
- [ ] **Action Required**: If images differ, see Issue #2 for remediation

### CloudFlare DNS Verification

- [ ] **Verify DNS records in CloudFlare** (request via #help-me-ops Slack channel if needed):
  - [ ] `ai.coder.com` → us-east-2 NLB
  - [ ] `*.ai.coder.com` → us-east-2 NLB
  - [ ] `oregon-proxy.ai.coder.com` → us-west-2 NLB
  - [ ] `*.oregon-proxy.ai.coder.com` → us-west-2 NLB
  - [ ] `emea-proxy.ai.coder.com` → eu-west-2 NLB
  - [ ] `*.emea-proxy.ai.coder.com` → eu-west-2 NLB

### Subdomain Routing

- [ ] **Test subdomain routing from Oregon proxy**:

  ```bash
  curl -I https://oregon-proxy.ai.coder.com/healthz
  # Test wildcard subdomain
  curl -I https://test-workspace.oregon-proxy.ai.coder.com
  ```

  - Result: **\*\*\*\***\_**\*\*\*\***

- [ ] **Test subdomain routing from London proxy**:

  ```bash
  curl -I https://emea-proxy.ai.coder.com/healthz
  # Test wildcard subdomain
  curl -I https://test-workspace.emea-proxy.ai.coder.com
  ```

  - Result: **\*\*\*\***\_**\*\*\*\***

- [ ] **Test subdomain routing from control plane**:

  ```bash
  curl -I https://ai.coder.com/healthz
  # Test wildcard subdomain
  curl -I https://test-workspace.ai.coder.com
  ```

  - Result: **\*\*\*\***\_**\*\*\*\***

---

## 3. Storage & Capacity

### Ephemeral Volume Storage

- [ ] **Check storage capacity per node across all regions**:

  ```bash
  # us-east-2 (Control Plane)
  kubectl top nodes --context=us-east-2

  # us-west-2 (Oregon)
  kubectl top nodes --context=us-west-2

  # eu-west-2 (London)
  kubectl top nodes --context=eu-west-2
  ```

  **us-east-2 Nodes**:
  - Node 1: **\*\*\*\***\_**\*\*\*\***% used
  - Node 2: **\*\*\*\***\_**\*\*\*\***% used
  - Node N: **\*\*\*\***\_**\*\*\*\***% used

  **us-west-2 Nodes**:
  - Node 1: **\*\*\*\***\_**\*\*\*\***% used
  - Node 2: **\*\*\*\***\_**\*\*\*\***% used

  **eu-west-2 Nodes**:
  - Node 1: **\*\*\*\***\_**\*\*\*\***% used
  - Node 2: **\*\*\*\***\_**\*\*\*\***% used

- [ ] **All nodes <60% storage utilization**
- [ ] **Action Required**: If any node >60%, add capacity or rebalance workloads

### Karpenter Scaling Readiness

- [ ] **Verify Karpenter is operational in all regions**:

  ```bash
  # Check Karpenter pods are running
  kubectl get pods -n karpenter --context=us-east-2
  kubectl get pods -n karpenter --context=us-west-2
  kubectl get pods -n karpenter --context=eu-west-2

  # Check NodePools are ready
  kubectl get nodepool --context=us-east-2
  kubectl get nodepool --context=us-west-2
  kubectl get nodepool --context=eu-west-2
  ```

- [ ] **Verify Karpenter NodeClaims are healthy**:
  ```bash
  kubectl get nodeclaims -A --context=us-east-2
  kubectl get nodeclaims -A --context=us-west-2
  kubectl get nodeclaims -A --context=eu-west-2
  ```

### Provisioner Scaling

**Current State**: 6 replicas (default org), 2 replicas each (experimental & demo orgs)
**Recommendation**: Scale to 8-10 replicas for default org if expecting >15 concurrent users

- [ ] **Check current provisioner replica counts**:

  ```bash
  kubectl get deployment -n coder -l app=coder-provisioner -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.replicas}{"\n"}{end}'
  ```

  - Default org provisioners: \***\*\_\*\*** replicas
  - Experimental org provisioners: \***\*\_\*\*** replicas
  - Demo org provisioners: \***\*\_\*\*** replicas

- [ ] **Scale provisioners if needed** for workshop:

  ```bash
  # Example: Scale default org provisioners to 10 replicas
  kubectl scale deployment coder-provisioner-default -n coder --replicas=10
  ```

  - [ ] Scaled to: \***\*\_\*\*** replicas for workshop

### LiteLLM Capacity

**Current State**: 4 replicas @ 2 vCPU / 4 GB each
**Recommendation**: May need scaling for >20 concurrent users

- [ ] **Verify LiteLLM replicas and health**:

  ```bash
  kubectl get deployment litellm -n litellm
  kubectl get pods -n litellm -l app=litellm
  ```

  - Current replicas: \***\*\_\*\***
  - All pods healthy: ✅ / ❌

- [ ] **If expecting >20 users, consider scaling LiteLLM**:
  ```bash
  kubectl scale deployment litellm -n litellm --replicas=6
  ```

### Resource Quotas

- [ ] **Verify workspace resource limits** are configured:
  - CPU limit per workspace: 2-4 vCPU (template configurable)
  - Memory limit per workspace: 4-8 GB (template configurable)
  - Storage limit per workspace: **\*\*\*\***\_**\*\*\*\***

- [ ] **Calculate total capacity**:
  - Expected concurrent workspaces: **\*\*\*\***\_**\*\*\*\***
  - Available capacity for concurrent workspaces: **\*\*\*\***\_**\*\*\*\***
  - Headroom percentage: **\*\*\*\***\_**\*\*\*\***

- [ ] **Headroom >30% for expected concurrent users**

---

## 4. Smoke Tests

### Control Plane Region (us-east-2)

**Available Templates**:

- Build from Scratch w/ Claude (2-4 vCPU, 4-8 GB)
- Build from Scratch w/ Goose (2-4 vCPU, 4-8 GB)
- Real World App w/ Claude (2-4 vCPU, 4-8 GB)

- [ ] **Create test workspace** using one of the available templates
  - Template used: **\*\*\*\***\_**\*\*\*\***
  - Workspace created successfully: ✅ / ❌
  - Time to ready: **\*\*\*\***\_**\*\*\*\***
  - Image pulled from ECR successfully: ✅ / ❌

- [ ] **Execute workload in test workspace**:
  - [ ] Test Claude Code CLI or Goose CLI (depending on template)
  - [ ] Verify LiteLLM connectivity
  - [ ] Test gh CLI authentication (optional GitHub auth)
  - Workload executed successfully: ✅ / ❌
  - Performance acceptable: ✅ / ❌

- [ ] **Delete test workspace**
  - Workspace deleted successfully: ✅ / ❌
  - Resources cleaned up: ✅ / ❌
  - Provisioner job completed: ✅ / ❌

### Oregon Proxy Cluster (us-west-2)

- [ ] **Create test workspace** via Oregon proxy
  - Template used: **\*\*\*\***\_**\*\*\*\***
  - Workspace created successfully: ✅ / ❌
  - Time to ready: **\*\*\*\***\_**\*\*\*\***
  - Routed through oregon-proxy.ai.coder.com: ✅ / ❌

- [ ] **Execute workload in test workspace**
  - Workload executed successfully: ✅ / ❌
  - Performance acceptable: ✅ / ❌
  - LiteLLM accessible from Oregon: ✅ / ❌

- [ ] **Delete test workspace**
  - Workspace deleted successfully: ✅ / ❌
  - Resources cleaned up: ✅ / ❌

### London Proxy Cluster (eu-west-2)

- [ ] **Create test workspace** via London proxy
  - Template used: **\*\*\*\***\_**\*\*\*\***
  - Workspace created successfully: ✅ / ❌
  - Time to ready: **\*\*\*\***\_**\*\*\*\***
  - Routed through emea-proxy.ai.coder.com: ✅ / ❌

- [ ] **Execute workload in test workspace**
  - Workload executed successfully: ✅ / ❌
  - Performance acceptable: ✅ / ❌
  - LiteLLM accessible from London: ✅ / ❌

- [ ] **Delete test workspace**
  - Workspace deleted successfully: ✅ / ❌
  - Resources cleaned up: ✅ / ❌

---

## 5. Monitoring & Alerting

### Dashboard Validation

- [ ] **Real-time workshop dashboard** is accessible
- [ ] **All metrics** are populating correctly:
  - [ ] Ephemeral volume storage per node
  - [ ] Concurrent workspace count
  - [ ] Workspace restart/failure rate
  - [ ] Image pull times
  - [ ] LiteLLM key expiration
  - [ ] Subdomain routing success rate
  - [ ] Node resource utilization

### Alert Configuration

- [ ] **Test critical alerts** (trigger test alert):
  - [ ] Storage capacity threshold alert
  - [ ] Workspace failure rate alert
  - [ ] LiteLLM key expiration alert

- [ ] **Verify alert destinations** are correct (Slack, email, etc.)
- [ ] **Confirm on-call rotation** is updated

---

## 6. Documentation & Support

- [ ] **Workshop agenda** finalized and shared with participants
- [ ] **Participant onboarding guide** up to date
- [ ] **Incident runbook** accessible to workshop team
- [ ] **Support team** notified and available during workshop

---

## 8. Pre-Workshop Scaling Actions

**Complete 1 day before workshop**:

- [ ] **Scale provisioner replicas** if expecting >15 users (documented above in section 3)
- [ ] **Scale LiteLLM replicas** if expecting >20 users (documented above in section 3)
- [ ] **Verify Karpenter has sufficient AWS quota** for expected node scaling:

  ```bash
  # Check current node count and instance types
  kubectl get nodes --show-labels | grep -E 'node.kubernetes.io/instance-type'

  # Verify AWS EC2 instance limits allow for growth
  aws service-quotas get-service-quota --service-code ec2 --quota-code L-1216C47A --region us-east-2
  ```

- [ ] **Disable or schedule around LiteLLM key rotation** to avoid workspace restarts during workshop
- [ ] **Notify #help-me-ops** on Slack if any CloudFlare DNS changes are needed

---

## 7. Final Go/No-Go

**All checks passed**: ✅ / ❌

**If NO**:

- Document blockers: **\*\*\*\***\_**\*\*\*\***
- Escalate to: **\*\*\*\***\_**\*\*\*\***
- Decision: Proceed / Postpone

**If YES**:

- Workshop is **GO** ✅
- Checklist completion time: **\*\*\*\***\_**\*\*\*\***
- Notes: **\*\*\*\***\_**\*\*\*\***

---

## Post-Validation Actions

- [ ] Share checklist results with workshop team
- [ ] Update capacity planning based on validation results
- [ ] Address any warnings or minor issues before workshop
- [ ] Archive completed checklist for historical reference

---

**Completed By**: **\*\*\*\***\_**\*\*\*\***  
**Sign-off**: **\*\*\*\***\_**\*\*\*\***  
**Date**: **\*\*\*\***\_**\*\*\*\***
