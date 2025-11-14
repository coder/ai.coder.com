# Workshop Incident Runbook

## Purpose

This runbook provides step-by-step procedures for diagnosing and resolving common incidents during monthly workshops.

---

## Incident Response Process

### 1. Initial Response

1. **Acknowledge** the incident in team chat
2. **Assess severity**:
   - **P0 (Critical)**: Complete service outage, data loss, security breach
   - **P1 (High)**: Significant degradation affecting multiple users
   - **P2 (Medium)**: Limited impact, workarounds available
   - **P3 (Low)**: Cosmetic issues, no user impact
3. **Assign incident commander** (P0/P1 only)
4. **Start incident log** (document timeline, actions, decisions)

### 2. Communication

- **Internal**: Update team in dedicated incident channel
- **Participants**: Provide status updates if impact is user-visible
- **Escalation**: Contact on-call engineer for P0/P1 incidents

### 3. Resolution & Follow-up

- Document root cause
- Create GitHub issue for permanent fix
- Update this runbook if new incident type discovered
- Include incident in post-workshop retrospective

---

## Common Incidents

### 1. Workspace Restarts / Self-Healing Loop

**Symptoms**:

- Workspaces repeatedly restarting
- Users losing progress
- Self-healing mechanisms triggering continuously

**Likely Causes**:

- Ephemeral volume storage exhaustion
- Resource contention (CPU, memory)
- Node capacity exceeded
- LiteLLM auxiliary addon key rotation (occurs every 4-5 hours, forces workspace restarts)

**Diagnosis**:

```bash
# Check node storage across all regions
kubectl top nodes --context=us-east-2
kubectl top nodes --context=us-west-2
kubectl top nodes --context=eu-west-2

kubectl get nodes -o wide --context=us-east-2

# Check ephemeral volume usage
kubectl get pods -A -o json | jq '.items[] | select(.spec.volumes != null) | {name: .metadata.name, namespace: .metadata.namespace, volumes: [.spec.volumes[] | select(.emptyDir != null)]}'

# Check for evicted pods across all regions
kubectl get pods -A --context=us-east-2 | grep Evicted
kubectl get pods -A --context=us-west-2 | grep Evicted
kubectl get pods -A --context=eu-west-2 | grep Evicted

# Check workspace pod events
kubectl describe pod <workspace-pod-name> -n <namespace>

# Check Karpenter node allocation
kubectl logs -l app.kubernetes.io/name=karpenter -n karpenter --tail=100 --context=us-east-2

# Check if LiteLLM key rotation is happening
kubectl logs -l app=litellm-key-rotator -n litellm --tail=50
```

**Resolution**:

**Immediate**:

1. **If caused by LiteLLM key rotation during workshop**:

   ```bash
   # Temporarily disable the auxiliary addon key rotation
   kubectl scale deployment litellm-key-rotator -n litellm --replicas=0

   # Workshop facilitators: Warn participants that workspaces may restart
   # Re-enable after workshop completes
   ```

2. Identify workspaces consuming excessive storage:
   ```bash
   kubectl exec -it <workspace-pod> -- df -h
   ```
3. If specific workspace is problematic, delete it:
   ```bash
   kubectl delete pod <workspace-pod> -n <namespace>
   ```
4. If cluster-wide issue, trigger Karpenter scaling or manually add nodes:

   ```bash
   # Check current NodePool capacity
   kubectl get nodepool --context=us-east-2

   # Check pending NodeClaims
   kubectl get nodeclaims -A --context=us-east-2

   # If Karpenter not scaling, check logs for issues
   kubectl logs -l app.kubernetes.io/name=karpenter -n karpenter --tail=200
   ```

**Temporary Workaround**:

- Pause new workspace deployments
- Ask participants to save work and stop workspaces
- Clean up unused workspaces

**Permanent Fix**:

- See GitHub Issue #1 for long-term storage optimization

---

### 2. Subdomain Routing Failures

**Symptoms**:

- Users cannot access workspaces via subdomain URLs
- 404 or DNS errors on workspace URLs
- Inconsistent routing across regions

**Likely Causes**:

- Image version mismatch between control plane and proxy clusters
- Private ECR mirror out of sync with `ghcr.io/coder/coder-preview`
- CloudFlare DNS misconfiguration
- Ingress controller misconfiguration
- DNS propagation delays

**Diagnosis**:

```bash
# Check Coder image versions across all clusters (must be identical)
kubectl get pods -n coder -o jsonpath='{.items[*].spec.containers[*].image}' --context=us-east-2
kubectl get pods -n coder -o jsonpath='{.items[*].spec.containers[*].image}' --context=us-west-2
kubectl get pods -n coder -o jsonpath='{.items[*].spec.containers[*].image}' --context=eu-west-2

# Verify private ECR mirror is up-to-date
crane digest ghcr.io/coder/coder-preview:latest
aws ecr describe-images --repository-name coder-preview --region us-east-2 --query 'sort_by(imageDetails,& imagePushedAt)[-1].imageDigest'

# Check proxy configurations
kubectl get svc -n coder --context=us-east-2
kubectl get svc -n coder --context=us-west-2
kubectl get svc -n coder --context=eu-west-2

# Check CloudFlare DNS resolution for all domains
dig ai.coder.com
dig oregon-proxy.ai.coder.com
dig emea-proxy.ai.coder.com
dig test-workspace.ai.coder.com
dig test-workspace.oregon-proxy.ai.coder.com
dig test-workspace.emea-proxy.ai.coder.com

# Check Network Load Balancers (NLB) are healthy
kubectl get svc -n coder -o wide

# Test proxy endpoints
curl -I https://ai.coder.com/healthz
curl -I https://oregon-proxy.ai.coder.com/healthz
curl -I https://emea-proxy.ai.coder.com/healthz
```

**Resolution**:

**Immediate**:

1. **If ECR mirror is out of sync**:

   ```bash
   # Pull latest preview image and push to ECR
   docker pull ghcr.io/coder/coder-preview:latest
   docker tag ghcr.io/coder/coder-preview:latest <aws-account-id>.dkr.ecr.us-east-2.amazonaws.com/coder-preview:latest
   aws ecr get-login-password --region us-east-2 | docker login --username AWS --password-stdin <aws-account-id>.dkr.ecr.us-east-2.amazonaws.com
   docker push <aws-account-id>.dkr.ecr.us-east-2.amazonaws.com/coder-preview:latest

   # Restart Coder pods in all regions
   kubectl rollout restart deployment/coder -n coder --context=us-east-2
   kubectl rollout restart deployment/coder -n coder --context=us-west-2
   kubectl rollout restart deployment/coder -n coder --context=eu-west-2
   ```

2. **If image versions mismatch across clusters**:

   ```bash
   # Restart Coder pods in affected cluster
   kubectl rollout restart deployment/coder -n coder --context=<affected-region>

   # Wait for rollout to complete
   kubectl rollout status deployment/coder -n coder --context=<affected-region>
   ```

3. **If CloudFlare DNS issue**:
   - Contact #help-me-ops on Slack immediately
   - Provide: Which domain is failing, expected NLB address, current DNS resolution
   - CloudFlare manages these domains:
     - `ai.coder.com` + `*.ai.coder.com` → us-east-2 NLB
     - `oregon-proxy.ai.coder.com` + `*.oregon-proxy.ai.coder.com` → us-west-2 NLB
     - `emea-proxy.ai.coder.com` + `*.emea-proxy.ai.coder.com` → eu-west-2 NLB

**Temporary Workaround**:

- Direct users to working region
- Use direct IP access if subdomain fails

**Permanent Fix**:

- See GitHub Issue #2 for image management standardization

---

### 3. LiteLLM Authentication Failures

**Symptoms**:

- Users cannot authenticate
- "Invalid API key" or similar errors
- AI features not working (Claude Code CLI, Goose CLI)
- Rate limiting errors

**Likely Causes**:

- Expired AWS Bedrock or GCP Vertex credentials
- LiteLLM auxiliary addon key rotation in progress (occurs every 4-5 hours)
- Rate limiting from AWS Bedrock or GCP Vertex
- LiteLLM service outage or pod crashes
- LiteLLM capacity exceeded (4 replicas @ 2 vCPU / 4 GB each)

**Diagnosis**:

```bash
# Check LiteLLM pod status and logs
kubectl get pods -n litellm -l app=litellm
kubectl logs -l app=litellm -n litellm --tail=100

# Check if key rotation is in progress
kubectl logs -l app=litellm-key-rotator -n litellm --tail=50

# Test LiteLLM endpoint
curl -I https://<litellm-alb-endpoint>/health

# Check AWS Bedrock credentials
kubectl get secret litellm-aws-credentials -n litellm -o jsonpath='{.data}'

# Check GCP Vertex credentials
kubectl get secret litellm-gcp-credentials -n litellm -o jsonpath='{.data}'

# Check LiteLLM resource usage
kubectl top pods -n litellm

# Test round-robin to AWS Bedrock and GCP Vertex
kubectl exec -n litellm deploy/litellm -- curl -X POST https://bedrock-runtime.us-east-1.amazonaws.com/model/anthropic.claude-v2/invoke
```

**Resolution**:

**Immediate**:

1. **If key rotation in progress during workshop**:

   ```bash
   # Wait for rotation to complete (typically <5 minutes)
   # Or temporarily pause rotation
   kubectl scale deployment litellm-key-rotator -n litellm --replicas=0

   # Re-enable after workshop
   kubectl scale deployment litellm-key-rotator -n litellm --replicas=1
   ```

2. **If LiteLLM capacity exceeded**:

   ```bash
   # Scale LiteLLM replicas from 4 to 6-8
   kubectl scale deployment litellm -n litellm --replicas=6

   # Monitor scaling
   kubectl get pods -n litellm -w
   ```

3. **If AWS/GCP credentials expired**:

   ```bash
   # Rotate AWS IAM role credentials
   # Update secret with new credentials
   kubectl create secret generic litellm-aws-credentials \
     --from-literal=aws-access-key-id=<new-key> \
     --from-literal=aws-secret-access-key=<new-secret> \
     --dry-run=client -o yaml | kubectl apply -f - -n litellm

   # Restart LiteLLM pods
   kubectl rollout restart deployment/litellm -n litellm
   ```

**Temporary Workaround**:

- If brief expiration, wait for key rotation
- Disable AI features temporarily if critical

**Permanent Fix**:

- See GitHub Issue #3 for key rotation automation

---

### 4. High Resource Contention

**Symptoms**:

- Slow workspace performance
- Timeouts during operations
- Elevated CPU/memory usage across cluster
- Provisioner jobs queuing or timing out

**Likely Causes**:

- Too many concurrent workspaces (workspaces use 2-4 vCPU, 4-8 GB each)
- Insufficient provisioner replicas (default: 6, experimental/demo: 2 each)
- Workload-heavy exercises
- Insufficient node capacity
- Karpenter not scaling fast enough

**Diagnosis**:

```bash
# Check cluster resource usage across all regions
kubectl top nodes --context=us-east-2
kubectl top pods -A --context=us-east-2

kubectl top nodes --context=us-west-2
kubectl top nodes --context=eu-west-2

# Check provisioner replica counts and status
kubectl get deployment -n coder -l app=coder-provisioner -o wide
kubectl get pods -n coder -l app=coder-provisioner

# Check provisioner logs for queuing
kubectl logs -n coder -l app=coder-provisioner --tail=100 | grep -i "queue\|wait\|timeout"

# Check Karpenter scaling
kubectl get nodeclaims -A --context=us-east-2
kubectl get nodepool --context=us-east-2
kubectl logs -l app.kubernetes.io/name=karpenter -n karpenter --tail=100

# Check workspace pod resource limits
kubectl describe pod <workspace-pod> -n <namespace> | grep -A 10 "Limits\|Requests"

# Count concurrent workspaces
kubectl get pods -A --context=us-east-2 | grep workspace | wc -l
```

**Resolution**:

**Immediate**:

1. **Scale provisioners** if jobs are queuing:

   ```bash
   # Scale default org provisioners from 6 to 10
   kubectl scale deployment coder-provisioner-default -n coder --replicas=10

   # Scale experimental/demo if needed
   kubectl scale deployment coder-provisioner-experimental -n coder --replicas=4
   kubectl scale deployment coder-provisioner-demo -n coder --replicas=4

   # Monitor provisioner scaling
   kubectl get pods -n coder -l app=coder-provisioner -w
   ```

2. **Trigger Karpenter to scale up nodes** if not auto-scaling:

   ```bash
   # Check Karpenter NodePool status
   kubectl get nodepool --context=us-east-2

   # Check for pending pods that should trigger scaling
   kubectl get pods -A --field-selector=status.phase=Pending

   # If Karpenter not scaling, check for errors
   kubectl logs -l app.kubernetes.io/name=karpenter -n karpenter --tail=200 | grep -i error
   ```

3. If nodes are at capacity, consider increasing instance sizes or manually adding nodes

**Temporary Workaround**:

- Reduce concurrent workspace count
- Switch to less resource-intensive exercises
- Stagger workspace deployments

**Permanent Fix**:

- Adjust resource limits per workspace
- Implement better capacity planning (see Issue #1)
- Add resource monitoring alerts (see Issue #6)

---

### 5. Image Pull Failures

**Symptoms**:

- Workspaces stuck in "ContainerCreating" state
- ImagePullBackOff errors
- Slow workspace startup times

**Likely Causes**:

- Private ECR registry authentication issues
- Network connectivity problems
- Rate limiting from ECR or GHCR
- Image doesn't exist or incorrect tag in private ECR
- ECR mirror out of sync with `ghcr.io/coder/coder-preview`

**Diagnosis**:

```bash
# Check pod status for image pull errors
kubectl get pods -A | grep -E 'ImagePull|ErrImagePull'

# Check pod events
kubectl describe pod <pod-name> -n <namespace> | grep -A 10 Events

# Check image pull secrets
kubectl get secrets -A | grep ecr
kubectl get secrets -A | grep docker

# Verify workspace image exists in private ECR
aws ecr describe-images --repository-name <workspace-image-repo> --region us-east-2

# Verify Coder image exists and is latest
aws ecr describe-images --repository-name coder-preview --region us-east-2 --query 'sort_by(imageDetails,& imagePushedAt)[-1]'
crane digest ghcr.io/coder/coder-preview:latest

# Test image pull from ECR
docker pull <aws-account-id>.dkr.ecr.us-east-2.amazonaws.com/coder-preview:latest
```

**Resolution**:

**Immediate**:

1. **If ECR authentication issue**:

   ```bash
   # Re-authenticate with ECR
   aws ecr get-login-password --region us-east-2 | docker login --username AWS --password-stdin <aws-account-id>.dkr.ecr.us-east-2.amazonaws.com

   # Update ECR pull secret in cluster
   kubectl create secret docker-registry ecr-pull-secret \
     --docker-server=<aws-account-id>.dkr.ecr.us-east-2.amazonaws.com \
     --docker-username=AWS \
     --docker-password=$(aws ecr get-login-password --region us-east-2) \
     -n <namespace> --dry-run=client -o yaml | kubectl apply -f -

   # Restart affected pods
   kubectl delete pod <pod-name> -n <namespace>
   ```

2. **If ECR mirror is out of sync**:

   ```bash
   # Pull latest from GHCR and push to private ECR
   docker pull ghcr.io/coder/coder-preview:latest
   docker tag ghcr.io/coder/coder-preview:latest <aws-account-id>.dkr.ecr.us-east-2.amazonaws.com/coder-preview:latest
   docker push <aws-account-id>.dkr.ecr.us-east-2.amazonaws.com/coder-preview:latest
   ```

3. **If workspace image missing**:

   ```bash
   # Check which workspace images are required
   # Templates use images from private ECR:
   # - Build from Scratch w/ Claude
   # - Build from Scratch w/ Goose
   # - Real World App w/ Claude (uses codercom/example-universal:ubuntu from DockerHub)

   # Verify images exist in ECR
   aws ecr describe-repositories --region us-east-2 | grep -E 'claude|goose'
   ```

4. Restart affected pods

**Temporary Workaround**:

- Use cached images if available on nodes
- Switch workshop participants to Real World App w/ Claude template (uses DockerHub instead of ECR)
- For critical issue, fall back to public DockerHub images if available

**Permanent Fix**:

- Implement image pre-caching on nodes
- Use image pull secrets with longer expiration
- See GitHub Issue #2 for image management improvements

---

### 6. Provisioner Failures

**Symptoms**:

- Workspaces stuck in "Pending" or "Starting" state
- Workspace create/delete/update operations timeout
- Provisioner job errors in Coder UI

**Likely Causes**:

- Insufficient provisioner replicas (default: 6, needs 8-10 for >15 users)
- Provisioner pod resource limits reached (500m CPU, 512 MB memory each)
- AWS IAM role issues for workspace provisioning
- Terraform state lock issues

**Diagnosis**:

```bash
# Check provisioner pod status
kubectl get pods -n coder -l app=coder-provisioner

# Check provisioner logs for errors
kubectl logs -n coder -l app=coder-provisioner --tail=200 | grep -i "error\|failed\|timeout"

# Check provisioner resource usage
kubectl top pods -n coder -l app=coder-provisioner

# Check how many provisioner jobs are running
kubectl logs -n coder -l app=coder-provisioner --tail=500 | grep -c "Acquired job"

# Check AWS IAM role used by provisioners
kubectl get sa coder-provisioner -n coder -o yaml | grep -A 5 annotations

# Check Coder API for provisioner status
curl -H "Coder-Session-Token: $CODER_SESSION_TOKEN" https://ai.coder.com/api/v2/provisioners
```

**Resolution**:

**Immediate**:

1. **Scale provisioner replicas**:

   ```bash
   # Current state: 6 replicas (default org)
   # Scale to 10 for workshops with >15 users
   kubectl scale deployment coder-provisioner-default -n coder --replicas=10

   # Monitor scaling
   kubectl get pods -n coder -l app=coder-provisioner -w
   ```

2. **If provisioners are OOMKilled or CPU throttled**:

   ```bash
   # Check for OOMKilled
   kubectl get pods -n coder -l app=coder-provisioner -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.containerStatuses[0].lastState.terminated.reason}{"\n"}{end}'

   # Temporarily increase resource limits (requires Helm/Terraform change)
   # Edit deployment to increase from 500m CPU / 512 MB to 1 CPU / 1 GB
   kubectl edit deployment coder-provisioner-default -n coder
   ```

3. **If AWS IAM role issue**:

   ```bash
   # Verify IAM role is properly attached
   kubectl describe sa coder-provisioner -n coder

   # Test AWS permissions from provisioner pod
   kubectl exec -n coder deploy/coder-provisioner-default -- aws sts get-caller-identity
   ```

**Temporary Workaround**:

- Stagger workspace deployments
- Ask participants to avoid simultaneous create/delete operations
- Prioritize workspace starts over deletes

**Permanent Fix**:

- See new GitHub issue for provisioner scaling automation
- Consider implementing provisioner autoscaling based on queue depth

---

## Emergency Contacts

| Role                | Name              | Contact |
| ------------------- | ----------------- | ------- |
| Infrastructure Lead |                   |         |
| On-Call Engineer    |                   |         |
| Platform Team Lead  |                   |         |
| Escalation Contact  | jullian@coder.com |         |

---

## Post-Incident Checklist

- [ ] Incident resolved and documented
- [ ] Root cause identified
- [ ] GitHub issue created for permanent fix
- [ ] Runbook updated with new learnings
- [ ] Team notified of resolution
- [ ] Participants notified if impacted
- [ ] Incident added to post-workshop retrospective

---

## Related Resources

- [Monthly Workshop Guide](./MONTHLY_WORKSHOP_GUIDE.md)
- [Pre-Workshop Checklist](./PRE_WORKSHOP_CHECKLIST.md)
- [Post-Workshop Retrospective Template](./POST_WORKSHOP_RETROSPECTIVE.md)
- GitHub Issues: [#1](https://github.com/coder/ai.coder.com/issues/1) [#2](https://github.com/coder/ai.coder.com/issues/2) [#3](https://github.com/coder/ai.coder.com/issues/3) [#6](https://github.com/coder/ai.coder.com/issues/6)
