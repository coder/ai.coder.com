---
display_name: Kubernetes (Deployment)
description: Provision Kubernetes Deployments as Coder workspaces
icon: ../../../site/static/icon/k8s.png
maintainer_github: coder
verified: true
tags: [kubernetes, container]
---

# Remote Development on Kubernetes Pods

Provision Kubernetes Pods as [Coder workspaces](https://coder.com/docs/workspaces) with this example template.

## Prerequisites

### Infrastructure

**Cluster**: This template requires an existing Kubernetes cluster.

**Container Image**: This template uses the [codercom/enterprise-base:ubuntu](https://github.com/coder/enterprise-images/tree/main/images/base) image with dev tools preinstalled. To add additional tools, extend this image or build your own.

**Storage**: A StorageClass must be available in the cluster to provision persistent volumes for workspace home directories.

### Authentication

This template authenticates using one of two methods:

1. **In-cluster authentication** (default): If Coder is running as a Pod on the same Kubernetes cluster, it uses the built-in ServiceAccount authentication.
2. **Kubeconfig authentication**: If Coder is running outside the cluster, set `use_kubeconfig = true` and ensure a valid `~/.kube/config` exists on the Coder host.

To use another [authentication method](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs#authentication), edit the template.

## Architecture

This template provisions the following resources:

| Resource | Type | Persistence |
|----------|------|-------------|
| Kubernetes Deployment | Compute | Ephemeral (recreated on restart) |
| Persistent Volume Claim | Storage | Persistent (mounted at `/home/coder`) |

When the workspace restarts, any tools or files outside the home directory are not persisted. To pre-bake tools into the workspace (e.g., `python3`), modify the container image. Individual developers can also [personalize](https://coder.com/docs/dotfiles) their workspaces with dotfiles.

## Configuration

### Template Variables

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `use_kubeconfig` | bool | `false` | Set to `true` if Coder runs outside the Kubernetes cluster |
| `namespace` | string | (required) | Kubernetes namespace for workspaces (must exist) |

### Workspace Parameters

Users can configure these options when creating a workspace:

| Parameter | Options | Default | Mutable |
|-----------|---------|---------|---------|
| CPU | 2, 4, 6, 8 cores | 2 | Yes |
| Memory | 2, 4, 6, 8 GB | 2 GB | Yes |
| Home Disk Size | 1-99999 GB | 10 GB | No |

## Features

### Included Applications

- **code-server**: VS Code in the browser, accessible via the Coder dashboard

### Workspace Metrics

The template collects and displays the following metrics in the Coder dashboard:

- CPU Usage (container and host)
- RAM Usage (container and host)
- Home Disk Usage
- Load Average (host)

### Resource Management

- **Requests**: 250m CPU, 512Mi memory (guaranteed minimum)
- **Limits**: Configurable via workspace parameters
- **Pod Anti-Affinity**: Workspaces are spread across nodes when possible

### Security

- Runs as non-root user (UID 1000)
- Uses fsGroup 1000 for volume permissions

## Usage

1. Create the template in Coder:
   ```bash
   coder templates create kubernetes --directory .
   ```

2. Create a workspace from the template:
   ```bash
   coder create my-workspace --template kubernetes
   ```

3. Access your workspace via the Coder dashboard or CLI:
   ```bash
   coder ssh my-workspace
   ```

## Customization

This template is designed as a starting point. Common customizations include:

- **Different base image**: Change the `image` in the container spec
- **Additional environment variables**: Add more `env` blocks
- **GPU support**: Add resource requests/limits for GPUs
- **Init containers**: Add setup containers that run before the main workspace
- **Sidecars**: Add additional containers (databases, proxies, etc.)
- **Node selection**: Add `node_selector` or modify `affinity` rules

## Troubleshooting

### Workspace stuck in "Starting" state

- Check if the namespace exists: `kubectl get ns <namespace>`
- Check pod events: `kubectl describe pod -n <namespace> coder-<workspace-id>`
- Verify StorageClass is available: `kubectl get sc`

### Cannot connect to workspace

- Ensure the Coder agent is running: check pod logs
- Verify network policies allow traffic to the workspace

### Persistent volume not binding

- Check PVC status: `kubectl get pvc -n <namespace>`
- Verify StorageClass supports dynamic provisioning
