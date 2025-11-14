# Postmortem: Agentic Workshop Incident - September 30, 2024

**Date:** September 30, 2024  
**Environment:** https://ai.coder.com  
**Severity:** High  
**Duration:** ~10 minutes into workshop until post-workshop fixes  
**Impact:** Multiple user workspaces died/restarted, wiping user progress during live workshop

---

## Executive Summary

During the Agentic Workshop on September 30, the AI demo environment experienced multiple cascading failures when approximately 10+ users simultaneously onboarded and deployed workspaces. While initial deployments succeeded, resource contention and architectural issues caused workspace instability, data loss, and service disruptions across the multi-region infrastructure. The incident revealed gaps in stress testing and highlighted limitations in the current architecture that were not apparent during smaller-scale internal testing.

---

## Timeline

**Pre-incident:** Workshop begins, users start onboarding process  
**T+0 min:** Initial workspace deployments roll through successfully  
**T+~10 min:** Workspaces begin competing for resources as workloads start running  
**T+~10 min:** LiteLLM authentication key briefly expires (few seconds)  
**T+~10 min:** Workspaces start dying and restarting, triggering self-healing mechanisms  
**T+~10 min:** User progress wiped due to ephemeral volume issues  
**T+~10 min:** Subdomain routing issues surface between Oregon and London proxy clusters  
**Post-workshop:** Fixes applied to address all identified issues

---

## Architecture Context

### Multi-Region Deployment

**Control Plane (us-east-2 - Ohio)**:

- Coder Server: 2 replicas @ 4 vCPU / 8 GB each
- External Provisioners: 6 replicas (default org) @ 500m CPU / 512 MB each
- LiteLLM Service: 4 replicas @ 2 vCPU / 4 GB each
- Primary domain: `ai.coder.com` + `*.ai.coder.com`

**Proxy Clusters**:

- Oregon (us-west-2): 2 replicas @ 500m CPU / 1 GB, domain: `oregon-proxy.ai.coder.com`
- London (eu-west-2): 2 replicas @ 500m CPU / 1 GB, domain: `emea-proxy.ai.coder.com`

**Image Management**:

- Source: `ghcr.io/coder/coder-preview` (non-GA preview for beta AI features)
- Mirrored to private AWS ECR (us-east-2)
- Critical dependency: ECR must stay in sync with GHCR

**DNS Management**:

- 6 domains managed in CloudFlare (control plane + 2 proxies, each with wildcard)
- Manual process via #help-me-ops Slack channel

---

## Root Causes

### 1. Resource Contention - Ephemeral Volume Storage

**Cause:** Limited node storage capacity for ephemeral volumes could not handle concurrent workspace workloads. Each workspace template consumes 2-4 vCPU and 4-8 GB memory, with ephemeral storage on node-local volumes.

**Impact:** Workspaces died and restarted when nodes exhausted storage, triggering self-healing that wiped user progress.

**Why it wasn't caught:**

- No stress testing with realistic concurrent user load (10+ users)
- Internal testing used lower concurrency
- Capacity planning didn't account for simultaneous workspace workloads
- No monitoring/alerting for ephemeral volume storage thresholds

**Technical Details:**

- Workspace templates allow 2-4 vCPU / 4-8 GB configuration
- ~10 concurrent workspaces @ 4 vCPU / 8 GB = 40+ vCPU / 80+ GB demand
- Ephemeral volumes for each workspace competed for node storage
- Karpenter auto-scaled nodes but storage capacity per node remained fixed

### 2. Image Management Inconsistencies

**Cause:** The non-GA Coder preview image (`ghcr.io/coder/coder-preview`) mirrored to private ECR fell out of sync between the control plane (us-east-2) and proxy clusters (us-west-2, eu-west-2).

**Impact:** Image version mismatches caused subdomain routing failures across regions. Workspaces couldn't be accessed via proxy URLs (`*.oregon-proxy.ai.coder.com`, `*.emea-proxy.ai.coder.com`).

**Why it wasn't caught:**

- Manual ECR mirroring process from GHCR is error-prone
- No automated validation of image digests across all clusters
- Issue only manifests under multi-region load with simultaneous deployments
- Pre-workshop checklist lacked image consistency verification

**Technical Details:**

- Image sync process:
  1. Pull from `ghcr.io/coder/coder-preview:latest`
  2. Tag and push to private ECR
  3. Deploy to all 3 regions (us-east-2, us-west-2, eu-west-2)
- During workshop, ECR mirror was stale
- Control plane ran newer image than proxies
- Subdomain routing logic failed due to version mismatch

### 3. LiteLLM Key Expiration

**Cause:** LiteLLM authentication key expired briefly during workshop. LiteLLM uses an auxiliary addon that rotates keys every 4-5 hours.

**Impact:** Brief service disruption (few seconds) for AI features (Claude Code CLI, Goose CLI). Key rotation also forces all workspaces to restart to consume new keys.

**Note:** Currently using open-source LiteLLM which has limited key management flexibility. Enterprise version not justified for current needs.

**Why it wasn't caught:**

- No pre-workshop validation of key expiration times
- Key rotation schedule not documented or considered in workshop planning
- No monitoring/alerting for upcoming key expirations

**Technical Details:**

- LiteLLM: 4 replicas @ 2 vCPU / 4 GB, round-robin between AWS Bedrock and GCP Vertex AI
- Auxiliary addon runs on 4-5 hour schedule
- Key rotation requires workspace restart to pick up new credentials
- If rotation occurs during workshop, causes mass workspace restarts

### 4. Provisioner Capacity Bottleneck

**Cause:** Default provisioner capacity (6 replicas @ 500m CPU / 512 MB) insufficient for ~10 concurrent users simultaneously creating workspaces.

**Impact:** Workspace create operations queued or timed out, causing delays and poor user experience.

**Why it wasn't caught:**

- No capacity planning guidelines for concurrent user scaling
- Provisioners are single-threaded (1 provisioner = 1 Terraform operation)
- No monitoring of provisioner queue depth
- Workshop planning didn't include provisioner pre-scaling

**Technical Details:**

- 10 users × 1 workspace each = 10 concurrent Terraform operations
- 6 provisioners = max 6 concurrent operations
- Remaining 4 operations queued, causing delays
- Recommendation: Scale to 8-10 replicas for 10-15 users

### 5. DNS Management Dependency

**Cause:** CloudFlare DNS managed manually via #help-me-ops Slack channel created potential for delays during incident response.

**Impact:** No immediate impact during workshop, but DNS issues would have been slow to resolve.

**Why it's a concern:**

- 6 domains to manage: control plane + 2 proxies (each with wildcard)
- No self-service for infrastructure team
- Dependency on ops team availability
- No automated validation of DNS configuration

---

## Impact Assessment

**Users Affected:** All workshop participants (~10+ concurrent users)  
**Data Loss:** User workspace progress wiped due to ephemeral volume restarts  
**Service Availability:** Degraded for ~10+ minutes during workshop  
**Business Impact:** Poor user experience during live demonstration/workshop event

**Metrics**:

- Workspace failure rate: ~40-50% (estimated, 4-5 workspaces restarted)
- Average workspace restart time: 2-3 minutes
- Number of incidents: 3 major (storage, image sync, key expiration)
- User-visible impact duration: ~10 minutes

---

## What Went Well

- Initial deployment phase worked correctly (first ~10 minutes)
- Self-healing mechanisms activated (though resulted in data loss)
- Karpenter successfully scaled nodes in response to demand
- LiteLLM key rotation was brief (few seconds)
- Issues were contained to the workshop environment (no production impact)
- Team responded post-workshop with comprehensive fixes
- Base infrastructure foundation is solid (EKS, Karpenter, multi-region setup)
- Multi-region architecture design is sound

---

## What Went Wrong

- No internal stress testing with realistic concurrent user load prior to workshop
- Ephemeral volume capacity planning insufficient for simultaneous workloads
- Image management strategy across multi-region clusters not robust
- No pre-workshop validation of authentication keys or key rotation schedule
- Lack of monitoring/alerting for resource contention thresholds
- Provisioner capacity not scaled proactively
- No pre-workshop checklist or validation procedures
- Manual processes (ECR sync, CloudFlare DNS) created points of failure
- No capacity planning guidelines for concurrent user scaling

---

## Action Items

### Completed (Post-Workshop)

- ✅ Applied fixes for all identified issues
- ✅ Created comprehensive incident documentation
- ✅ Documented architecture and component details
- ✅ Created pre-workshop validation checklist
- ✅ Created incident runbook
- ✅ Established GitHub tracking issues

### High Priority (Before Next Workshop)

**Storage & Capacity** (Issue #1)

- [ ] Audit current ephemeral volume allocation per node
- [ ] Calculate storage requirements for target concurrent workspace count
- [ ] Implement storage capacity monitoring and alerting
- [ ] Define resource limits per workspace to prevent node exhaustion
- [ ] Test with realistic concurrent user load

**Image Management** (Issue #2, Issue #7)

- [ ] Automate ECR image mirroring from `ghcr.io/coder/coder-preview`
- [ ] Implement pre-deployment validation of image digests across all clusters
- [ ] Add to pre-workshop checklist
- [ ] Document rollback procedure for bad images

**LiteLLM Key Management** (Issue #3)

- [ ] Implement monitoring/alerting for key expiration (7, 3, 1 day warnings)
- [ ] Document key rotation procedure
- [ ] Add key expiration check to pre-workshop checklist
- [ ] Disable/schedule key rotation around workshops

**Pre-Workshop Validation** (Issue #4)

- [ ] Complete pre-workshop checklist 2 days before each workshop
- [ ] Validate LiteLLM keys, image consistency, storage capacity
- [ ] Test subdomain routing across all regions
- [ ] Scale provisioners based on expected attendance
- [ ] Confirm monitoring and alerting is operational

**Provisioner Scaling** (Issue #8)

- [ ] Document scaling recommendations based on concurrent user count
- [ ] Scale provisioners 1 day before workshops (6 → 8-10 for 10-15 users)
- [ ] (Long-term) Implement provisioner auto-scaling based on queue depth

**Monitoring & Alerting** (Issue #6)

- [ ] Ephemeral volume storage capacity per node (alert at 70%, 85%, 95%)
- [ ] Concurrent workspace count
- [ ] Workspace restart/failure rate
- [ ] Image pull times across clusters
- [ ] LiteLLM key expiration
- [ ] Subdomain routing success rate
- [ ] Provisioner queue depth

### Medium Priority (1-3 months)

**CloudFlare DNS Automation** (Issue #9)

- [ ] Migrate CloudFlare DNS to Terraform
- [ ] Enable self-service DNS changes via PR workflow
- [ ] Add DNS validation to CI/CD pipeline
- [ ] Implement monitoring for DNS resolution

**Monthly Workshop Cadence** (Issue #5)

- [ ] Establish monthly workshop schedule
- [ ] Develop workshop content/agenda
- [ ] Define success metrics
- [ ] Create feedback collection mechanism
- [ ] Track month-over-month improvements

### Long-Term (3+ months)

**Stress Testing Automation**

- [ ] Build internal stress testing tooling
- [ ] Simulate concurrent user load
- [ ] Automate capacity validation
- [ ] Integrate into CI/CD pipeline

**Architectural Improvements**

- [ ] Evaluate persistent storage options to prevent data loss
- [ ] Consider workspace state backup/restore mechanisms
- [ ] Implement provisioner auto-scaling (HPA based on queue depth)
- [ ] Optimize ephemeral volume allocation strategy

---

## Lessons Learned

### What We Learned

1. **Production-like testing is essential:** Internal testing without realistic concurrent load is insufficient for demo/workshop environments. The gap between "works in testing" and "works at scale" is significant.

2. **Capacity planning needs real-world data:** Architectural assumptions (storage, provisioners, LiteLLM) must be validated under actual user load patterns. Theoretical capacity ≠ practical capacity.

3. **Manual processes don't scale:** ECR image syncing and CloudFlare DNS management via Slack requests create bottlenecks and points of failure during incidents.

4. **Multi-region consistency is hard:** Keeping images, configurations, and services synchronized across us-east-2, us-west-2, and eu-west-2 requires automation and validation.

5. **Key rotation timing matters:** LiteLLM's 4-5 hour rotation schedule must be coordinated with workshop timing to avoid forced workspace restarts during events.

6. **Provisioner scaling is critical:** Single-threaded Terraform operations mean provisioner count directly determines concurrent workspace operation capacity.

7. **Pre-event validation is non-negotiable:** A structured checklist covering infrastructure, capacity, authentication, and routing prevents preventable issues.

8. **Monthly cadence provides continuous validation:** Regular workshops will surface optimization opportunities and prevent regressions. The base infrastructure is solid; now we need operational refinement.

### What We'll Do Differently

1. **Always run pre-workshop checklist** 2 days before events
2. **Scale provisioners and LiteLLM proactively** based on expected attendance
3. **Disable LiteLLM key rotation** during workshop windows
4. **Validate image consistency** across all regions before workshops
5. **Monitor ephemeral storage** and alert before capacity issues arise
6. **Automate manual processes** (ECR sync, DNS management)
7. **Conduct monthly workshops** to continuously stress test and improve
8. **Document everything** for faster incident response and knowledge sharing

### Process Improvements

1. **Pre-Workshop Checklist:** Mandatory 2-day pre-event validation covering all infrastructure components
2. **Incident Runbook:** Step-by-step procedures for common failure scenarios
3. **Capacity Planning:** Clear guidelines for scaling based on concurrent user count
4. **Monitoring Dashboard:** Real-time visibility during workshops for proactive issue detection
5. **Post-Workshop Retrospective:** Structured feedback loop to track improvements month-over-month

---

## Technical Recommendations

### Immediate (Week 1)

1. Implement ephemeral storage monitoring with alerting
2. Create automated ECR sync job (GitHub Actions or AWS Lambda)
3. Document provisioner scaling procedure in runbook
4. Add LiteLLM key expiration to monitoring

### Short-term (Month 1)

1. Migrate CloudFlare DNS to Terraform
2. Implement image digest validation across clusters
3. Set up workshop-specific monitoring dashboard
4. Create provisioner HPA based on CPU/memory

### Long-term (Quarter 1)

1. Build stress testing automation
2. Implement provisioner queue depth monitoring and auto-scaling
3. Evaluate persistent storage options for workspace data
4. Expand to additional demo environments (coderdemo.io, devcoder.io)

---

## Success Metrics

Track these metrics month-over-month:

**Platform Stability**:

- Workspace restart/failure rate: Target <2%
- Incidents with user-visible impact: Target 0
- Storage contention events: Target 0
- Subdomain routing errors: Target 0
- Average workspace start time: Target <2 minutes

**Workshop Quality**:

- Participant satisfaction score: Target 4.5+/5
- Percentage completing workshop: Target >90%
- Number of blockers encountered: Target <3

**Operational Efficiency**:

- Pre-workshop checklist completion time: Target <30 minutes
- Time to resolve incidents: Target <5 minutes
- Manual interventions required: Target <2 per workshop

---

## Related Resources

### Documentation

- [Architecture Overview](./workshops/ARCHITECTURE.md)
- [Monthly Workshop Guide](./workshops/MONTHLY_WORKSHOP_GUIDE.md)
- [Pre-Workshop Checklist](./workshops/PRE_WORKSHOP_CHECKLIST.md)
- [Incident Runbook](./workshops/INCIDENT_RUNBOOK.md)
- [Post-Workshop Retrospective Template](./workshops/POST_WORKSHOP_RETROSPECTIVE.md)
- [Participant Guide](./workshops/PARTICIPANT_GUIDE.md)

### GitHub Issues

- [#1 - Optimize ephemeral volume storage capacity](https://github.com/coder/ai.coder.com/issues/1)
- [#2 - Standardize image management across clusters](https://github.com/coder/ai.coder.com/issues/2)
- [#3 - Improve LiteLLM key rotation and monitoring](https://github.com/coder/ai.coder.com/issues/3)
- [#4 - Create pre-workshop validation checklist](https://github.com/coder/ai.coder.com/issues/4)
- [#5 - Establish monthly workshop cadence](https://github.com/coder/ai.coder.com/issues/5)
- [#6 - Implement comprehensive monitoring and alerting](https://github.com/coder/ai.coder.com/issues/6)
- [#7 - Automate ECR image mirroring](https://github.com/coder/ai.coder.com/issues/7)
- [#8 - Implement provisioner auto-scaling](https://github.com/coder/ai.coder.com/issues/8)
- [#9 - Automate CloudFlare DNS management](https://github.com/coder/ai.coder.com/issues/9)

---

## Approvals

**Infrastructure Team Lead**: **\*\*\*\***\_**\*\*\*\***  
**Product Team Lead**: **\*\*\*\***\_**\*\*\*\***  
**Date**: **\*\*\*\***\_**\*\*\*\***

---

**Prepared by:** Dave Ahr  
**Review Date:** October 2024  
**Next Review:** After first monthly workshop
