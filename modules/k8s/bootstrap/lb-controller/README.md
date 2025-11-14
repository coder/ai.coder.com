### Adopting an existing ALB

Before reading into this, this applies only if:

- 1. The Load Balancer has the "delete_protection" annotation set to "true", and if the Load Balancer was being already managed prior.

In case you run into any issues where you accidently delete this Helm chart, you can just "re-adopt" the load balancer.

Simply, copy the old manifest, `kubectl get svc -n coder coder -o yaml`, and remove the following attributes:

```yaml
metadata:
  deletionTimestamp: ...
  deletionGracePeriodSeconds: ...
  finalizers: ...
  uid: ...
  resourceVersion: ...
  managedFields: ...
  creationTimestamp: ...
status: ...
```

Edit the currently applied manifest and remove the "finalizers" attribute.

Force delete the currently applied manifest via `kubectl delete svc coder -n coder --force --grace-period=0`.

Now, apply the copied manifest, and your're done!
