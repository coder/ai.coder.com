# Cost Optimization Strategy for Coder Demo

## Mixed Capacity Approach

### Node Group Strategy

**System Nodes (ON_DEMAND)**

- **Purpose**: Run critical Kubernetes infrastructure
- **Workloads**: CoreDNS, kube-proxy, metrics-server, cert-manager, AWS LB Controller
- **Size**: t4g.medium (ARM Graviton)
- **Count**: 1-2 nodes minimum
- **Cost**: ~$24/month (1 node) to $48/month (2 nodes)

**Application Nodes (MIXED: 20% On-Demand, 80% Spot via Karpenter)**

- **Purpose**: Run Coder server and workspaces
- **Spot Savings**: 70-90% cost reduction
- **Interruption Risk**: Mitigated by:
  - Multiple instance types (diversified Spot pools)
  - Karpenter auto-rebalancing
  - Pod Disruption Budgets

### Karpenter NodePool Configuration

#### 1. Coder Server NodePool (ON_DEMAND Priority)

```yaml
capacity_type: ["on-demand", "spot"] # Prefer On-Demand, fallback to Spot
weight:
  on-demand: 100 # Higher priority
  spot: 10
```

#### 2. Coder Workspace NodePool (SPOT Priority)

```yaml
capacity_type: ["spot", "on-demand"] # Prefer Spot, fallback to On-Demand
weight:
  spot: 100 # Higher priority
  on-demand: 10
```

### Risk Mitigation

**Spot Interruption Handling:**

1. **2-minute warning** → Karpenter automatically provisions replacement
2. **Multiple instance types** → 15+ types reduces interruption rate to <1%
3. **Pod Disruption Budgets** → Ensures minimum replicas always running
4. **Karpenter Consolidation** → Automatically moves pods before termination

**Example Instance Type Diversity:**

```
Spot Pool: t4g.medium, t4g.large, t3a.medium, t3a.large,
           m6g.medium, m6g.large, m6a.medium, m6a.large
```

### Cost Breakdown

| Component          | Instance Type | Capacity  | Monthly Cost  |
| ------------------ | ------------- | --------- | ------------- |
| System Nodes (2)   | t4g.medium    | ON_DEMAND | $48           |
| Coder Server (2)   | t4g.large     | 80% SPOT  | $28 (vs $140) |
| Workspaces (avg 5) | t4g.xlarge    | 90% SPOT  | $75 (vs $750) |
| **Total**          |               | **Mixed** | **$151/mo**   |

**vs All On-Demand:** $938/month → **84% savings**

### Dynamic Scaling

**Low Usage (nights/weekends):**

- Scale to zero workspaces
- Keep 1 system node + 1 Coder server node
- Cost: ~$48/month during idle

**High Usage (business hours):**

- Auto-scale workspaces on Spot
- Karpenter provisions nodes in <60 seconds
- Cost: ~$150-200/month during peak

### Monitoring & Alerts

**CloudWatch Alarms:**

- Spot interruption rate > 5%
- Available On-Demand capacity < 20%
- Karpenter provisioning failures

**Response:**

- Automatic fallback to On-Demand
- Email alerts to ops team
- Karpenter adjusts instance type mix

## Implementation Timeline

1. ✅ Deploy EKS with ON_DEMAND system nodes
2. ⏳ Deploy Karpenter
3. ⏳ Configure mixed-capacity NodePools
4. ⏳ Deploy Coder with node affinity rules
5. ⏳ Test Spot interruption handling
6. ⏳ Enable auto-scaling policies

## Fallback Plan

If Spot becomes unreliable (rare):

1. Update Karpenter NodePool to 100% On-Demand
2. `kubectl apply -f nodepool-ondemand.yaml`
3. Karpenter gracefully migrates pods
4. Takes ~5 minutes, zero downtime

## Best Practices

✅ **DO:**

- Use multiple Spot instance types (10+)
- Set Pod Disruption Budgets
- Monitor Spot interruption rates
- Test failover regularly

❌ **DON'T:**

- Run databases on Spot (use RDS)
- Use Spot for single-replica critical services
- Rely on single instance type for Spot
