# Infrastructure Best Practices for Coder Deployment

This document outlines the architectural decisions, best practices, and rationale behind the Coder infrastructure deployment on AWS EKS. Use this as a reference when discussing technical implementation with customers and prospects.

---

## Table of Contents

1. [Load Balancer Architecture](#load-balancer-architecture)
2. [DNS and Multi-Region Setup](#dns-and-multi-region-setup)
3. [LiteLLM Integration Architecture](#litellm-integration-architecture)
4. [Helm Chart Management](#helm-chart-management)
5. [Security Considerations](#security-considerations)

---

## Load Balancer Architecture

### Decision: Network Load Balancer (NLB) with TLS Termination

**What We Did:**

- Deployed NLB with TLS termination using ACM certificates
- Configured `CODER_TLS_ENABLE = "false"` on Coder server
- NLB terminates TLS and forwards plain HTTP to backend

**Why This Approach:**

#### NLB Advantages for Coder

1. **Lower Latency** - Layer 4 (TCP) vs Layer 7 (HTTP)
   - Less protocol overhead
   - Direct connection forwarding
   - Critical for long-lived WebSocket connections (terminals, live updates)

2. **Source IP Preservation**
   - NLB preserves client source IP addresses
   - Essential for Coder's audit logs and security monitoring
   - No need to parse `X-Forwarded-For` headers

3. **Static IP Addresses**
   - NLB provides static IPs per availability zone
   - Easier for enterprise firewall rules and allowlists
   - ALB uses dynamic IPs (requires DNS-based allowlisting)

4. **Connection Handling**
   - Better for long-lived persistent connections
   - Coder workspaces maintain extended connections
   - Lower overhead per connection

5. **Cost Efficiency**
   - NLB: $0.0225/hour + $0.006/GB processed
   - ALB: $0.0225/hour + $0.008/GB processed + per-rule charges
   - Lower cost at high volume

#### TLS Termination at NLB

**Common Misconception:**

> "NLBs don't terminate TLS - they're Layer 4 pass-through only"

**Reality:**
NLBs **DO support TLS termination** when configured with ACM certificates via the AWS Load Balancer Controller.

**Configuration:**

```hcl
service_annotations = {
  "service.beta.kubernetes.io/aws-load-balancer-ssl-cert"  = data.aws_acm_certificate.coder.arn
  "service.beta.kubernetes.io/aws-load-balancer-ssl-ports" = "443"
}
```

**Traffic Flow:**

```
User (HTTPS:443) → NLB (terminates TLS) → Coder Backend (HTTP:8080)
```

**Coder Configuration:**

```hcl
env_vars = {
  CODER_REDIRECT_TO_ACCESS_URL = "false"  # Prevent redirect loops
  CODER_TLS_ENABLE             = "false"  # NLB handles TLS
  CODER_SECURE_AUTH_COOKIE     = "true"   # Users connect via HTTPS
}
```

**Official Documentation:**

- [AWS: Create TLS Listener for NLB](https://docs.aws.amazon.com/elasticloadbalancing/latest/network/create-tls-listener.html)
- [AWS: NLB TLS Termination Announcement](https://aws.amazon.com/blogs/aws/new-tls-termination-for-network-load-balancers/)
- [AWS Load Balancer Controller: NLB TLS Termination](https://kubernetes-sigs.github.io/aws-load-balancer-controller/latest/guide/use_cases/nlb_tls_termination/)

#### When to Use ALB Instead

Consider ALB only if you need:

- Path-based routing (`/api` → service A, `/web` → service B)
- Host-based routing (multiple domains to different backends)
- HTTP-level features (redirects, header manipulation, authentication)
- WAF (Web Application Firewall) integration
- More detailed HTTP metrics

**For Coder:** These features are not needed - it's a single application without complex routing requirements.

---

## DNS and Multi-Region Setup

### Architecture Overview

**Root Domain:** `coderdemo.io` (Route53 hosted zone)

**DNS Records:**

#### 1. Latency-Based Routing (Automatic)

```
coderdemo.io              → Routes to nearest region (us-east-2 or us-west-2)
*.coderdemo.io            → Wildcard for workspace apps (latency-routed)
```

**Configuration:**

```hcl
resource "aws_route53_record" "coder_latency" {
  zone_id        = var.hosted_zone_id
  name           = var.domain_name
  type           = "A"
  set_identifier = var.set_identifier  # e.g., "us-east-2"

  alias {
    name                   = local.nlb_hostname
    zone_id                = data.aws_lb.coder_nlb.zone_id
    evaluate_target_health = true
  }

  latency_routing_policy {
    region = var.cluster_region
  }

  health_check_id = aws_route53_health_check.coder[0].id
}
```

#### 2. Region-Specific Subdomains (Manual Selection)

```
us-east-2.coderdemo.io    → Force Ohio region
us-west-2.coderdemo.io    → Force Oregon region
*.us-east-2.coderdemo.io  → Ohio workspace apps
*.us-west-2.coderdemo.io  → Oregon workspace apps
```

**Use Case:**
Instructor in East Coast can join West Coast customer demo by using `us-west-2.coderdemo.io` instead of relying on latency-based routing.

### Benefits

1. **Automatic Failover**
   - Route53 health checks monitor each region
   - Unhealthy regions automatically removed from rotation
   - Users transparently routed to healthy region

2. **Performance Optimization**
   - Users connect to geographically nearest region
   - Lower latency for all interactions
   - Better experience for global teams

3. **Manual Override**
   - Region-specific URLs allow explicit region selection
   - Useful for demos, testing, or specific customer requirements
   - No code changes needed - just use different URL

### Multi-Region Coder Visibility

**Current State:**

- Only `us-east-2` appears in Coder's region dropdown
- `us-west-2` infrastructure code exists but not deployed

**For us-west-2 to Appear:**

1. Deploy ACM certificates (`infra/aws/us-west-2/acm/`)
2. Deploy Coder server (`infra/aws/us-west-2/k8s/coder-server/`)
3. Deploy Route53 records (`infra/aws/us-west-2/route53/`)
4. Ensure shared RDS database or database replication

**Important:** Both regions must use the same database for unified user accounts and workspace state.

---

## LiteLLM Integration Architecture

### Decision: Separate Service with Subdomain

**Architecture:**

```
coderdemo.io                → Coder (latency-routed)
llm.coderdemo.io            → LiteLLM (separate NLB)
```

**Deployment:**

- LiteLLM: Separate Kubernetes deployment with own NLB
- Each Coder workspace namespace gets LiteLLM API keys via secret rotation
- Keys automatically rotated from AWS Secrets Manager

**Why This Approach:**

#### Option 1: Separate Subdomain ✅ (Implemented)

**Advantages:**

- Keep NLB for both services (no ALB needed)
- Clean separation of concerns
- Independent scaling and monitoring
- No path rewriting complexity

#### Option 2: Path-Based Routing (Not Recommended)

```
coderdemo.io/        → Coder
coderdemo.io/v1/*    → LiteLLM
```

**Disadvantages:**

- Requires switching to ALB
- More complex configuration
- Potential URL rewriting issues
- No clear benefit for this use case

#### Option 3: Internal Only (Alternative)

**For Maximum Security:**

- Don't expose LiteLLM externally at all
- Coder communicates via internal Kubernetes service DNS
- Only Coder → LiteLLM traffic allowed
- No additional load balancer needed

### Current Implementation

**LiteLLM Service:** `infra/aws/us-east-2/k8s/litellm/main.tf`

- 4 replicas with 2 CPU / 4Gi memory each
- Own ACM certificate for TLS termination
- Connected to PostgreSQL (RDS) and Redis
- Automatic key generation and rotation

**Workspace Integration:** `infra/aws/us-east-2/k8s/coder-ws/main.tf`

```hcl
module "default-ws-litellm-rotate-key" {
  source        = "../../../../../modules/k8s/bootstrap/litellm-rotate-key"
  namespace     = "coder-ws"
  secret_id     = var.aws_secret_id
  secret_region = var.aws_secret_region
}
```

**Key Rotation:**

- Keys fetched from AWS Secrets Manager
- Injected as Kubernetes secrets into workspace namespaces
- Workspaces use keys to make LLM API calls through LiteLLM
- Rotation happens automatically without workspace downtime

---

## Helm Chart Management

### Decision: Enable `upgrade_install` on All Helm Releases

**What We Did:**
Added `upgrade_install = true` to all `helm_release` resources across the codebase.

**Files Updated:**

- `modules/k8s/bootstrap/karpenter/main.tf`
- `modules/k8s/bootstrap/ebs-controller/main.tf`
- `modules/k8s/bootstrap/lb-controller/main.tf`
- `modules/k8s/bootstrap/cert-manager/main.tf`
- `modules/k8s/bootstrap/coder-server/main.tf`
- `modules/k8s/bootstrap/coder-proxy/main.tf`
- `modules/k8s/bootstrap/metrics-server/main.tf`

**Configuration:**

```hcl
resource "helm_release" "example" {
  name             = "example"
  namespace        = var.namespace
  chart            = "example"
  repository       = "https://charts.example.com"
  create_namespace = true
  upgrade_install  = true  # ← Critical for idempotent deployments
  skip_crds        = false
  wait             = true
  wait_for_jobs    = true
  version          = var.chart_version
}
```

**Why This Matters:**

1. **Idempotent Terraform Applies**
   - Without `upgrade_install`: Terraform fails if release already exists
   - With `upgrade_install`: Terraform upgrades existing release or installs new one
   - Essential for repeatable deployments

2. **Version Management**
   - Allows Terraform to manage chart version upgrades
   - No manual `helm upgrade` commands needed
   - Declarative infrastructure-as-code

3. **CI/CD Integration**
   - Pipelines can safely re-run Terraform apply
   - No "already exists" errors in automation
   - Cleaner error handling

**Helm Provider Version:**

```hcl
helm = {
  source  = "hashicorp/helm"
  version = "3.1.1"  # upgrade_install re-added in this version
}
```

**Historical Context:**
The `upgrade_install` parameter was temporarily removed from the Helm provider in earlier versions, leading to comments in code saying it was "invalid". It was re-added in version 3.1.1 and should now be used as a best practice.

---

## Security Considerations

### TLS/SSL Certificate Management

**ACM Certificates:**

```hcl
data "aws_acm_certificate" "coder" {
  domain      = trimsuffix(trimprefix(var.coder_access_url, "https://"), "/")
  statuses    = ["ISSUED"]
  most_recent = true
}
```

**Best Practices:**

1. Use ACM for automatic certificate renewal
2. Fetch certificates dynamically (don't hardcode ARNs)
3. Filter by `ISSUED` status to avoid revoked certs
4. Use `most_recent` for automatic updates

### Service Account Permissions

**Principle of Least Privilege:**

```hcl
oidc_principals = {
  "${var.cluster_oidc_provider_arn}" = [
    "system:serviceaccount:${var.namespace}:coder"
  ]
}
```

**Why:**

- Restrict IAM role assumption to specific service accounts
- Prevents any pod from assuming sensitive roles
- Scoped to specific namespace and service account name

### Source IP Preservation

**NLB Advantage:**

- Client source IP preserved in connection
- Available in Coder's audit logs
- No header parsing needed
- Better security monitoring and rate limiting

**With ALB:**

- Source IP only available in `X-Forwarded-For` header
- Application must parse headers
- Less reliable (headers can be spoofed)

---

## Key Takeaways for Sales Engineers

### When Discussing Load Balancers

1. **NLB is the right choice for Coder**
   - Optimized for long-lived WebSocket connections
   - Lower latency than ALB
   - Source IP preservation for audit logs
   - Static IPs for enterprise firewalls

2. **NLB DOES support TLS termination**
   - Common misconception that it doesn't
   - Fully supported via ACM certificates
   - Show AWS documentation if questioned

3. **ALB only needed if:**
   - Path-based routing required
   - WAF integration needed
   - HTTP-specific features required
   - None of these apply to standard Coder deployments

### When Discussing Multi-Region

1. **Latency-based routing provides:**
   - Automatic performance optimization
   - Built-in failover
   - No user action required

2. **Region-specific URLs allow:**
   - Manual region override
   - Demo flexibility
   - Testing and troubleshooting

3. **Shared database is critical:**
   - Users need unified accounts across regions
   - Workspace state must be accessible everywhere
   - Consider RDS read replicas for performance

### When Discussing LiteLLM

1. **Separate subdomain approach:**
   - Keeps architecture simple
   - No ALB needed
   - Independent scaling
   - Clear separation of concerns

2. **Automatic key rotation:**
   - Security best practice
   - No manual key management
   - Zero downtime rotation
   - AWS Secrets Manager integration

3. **Internal-only option available:**
   - Maximum security
   - No external exposure
   - Simpler architecture
   - Recommended if no external access needed

### When Discussing Infrastructure as Code

1. **`upgrade_install = true` is critical:**
   - Enables idempotent Terraform applies
   - Required for CI/CD pipelines
   - Prevents deployment failures
   - Standard best practice

2. **Terraform module structure:**
   - Reusable across regions
   - Consistent configuration
   - Easy to add new regions
   - Clear separation of concerns

---

## Additional Resources

### AWS Documentation

- [NLB TLS Termination](https://docs.aws.amazon.com/elasticloadbalancing/latest/network/create-tls-listener.html)
- [Route53 Latency-Based Routing](https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/routing-policy-latency.html)
- [ACM Certificate Management](https://docs.aws.amazon.com/acm/latest/userguide/acm-overview.html)

### Kubernetes Documentation

- [AWS Load Balancer Controller](https://kubernetes-sigs.github.io/aws-load-balancer-controller/latest/)
- [Service Annotations](https://kubernetes-sigs.github.io/aws-load-balancer-controller/latest/guide/service/annotations/)

### Coder Documentation

- [Coder Configuration](https://coder.com/docs/admin/configure)
- [External Authentication](https://coder.com/docs/admin/external-auth)
- [Enterprise Features](https://coder.com/docs/admin/enterprise)

---

## Version History

- **2025-11-25**: Initial documentation of best practices
- Added NLB vs ALB comparison and rationale
- Documented DNS multi-region architecture
- Explained LiteLLM integration approach
- Covered Helm `upgrade_install` best practice
- Included security considerations

---

## Questions or Feedback

For technical questions about this architecture, contact the infrastructure team.
For customer-specific discussions, work with your Solutions Architect.
