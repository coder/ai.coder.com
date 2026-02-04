---
display_name: Claude Code on Coder
description: Provision Kubernetes workspaces with Claude Code and code-server
icon: ../../../site/static/icon/claude.svg
maintainer_github: coder
verified: true
tags: [kubernetes, container, claude, ai]
---

# Kubernetes Workspaces with Claude Code

Provision Kubernetes-based [Coder workspaces](https://coder.com/docs/workspaces) with Claude Code and code-server pre-configured.

## Features

- **Claude Code**: AI-powered coding assistant via the [claude-code module](https://registry.coder.com/modules/claude-code)
- **code-server**: Browser-based VS Code experience
- **Persistent Storage**: Home directory persists across workspace restarts
- **Resource Control**: Configurable CPU, memory, and disk allocation
- **Workspace Metrics**: Real-time CPU, memory, and disk usage displayed in the dashboard

## Prerequisites

### Infrastructure

- **Kubernetes Cluster**: An existing Kubernetes cluster with sufficient resources
- **Namespace**: A pre-existing namespace for workspace deployments
- **Storage Class**: A default storage class for persistent volume claims

### Authentication

This template supports two authentication methods:

1. **In-cluster authentication** (default): When Coder runs as a pod in the same cluster, it uses the ServiceAccount for authentication. Set `use_kubeconfig = false`.

2. **Kubeconfig authentication**: When Coder runs outside the cluster, provide a valid `~/.kube/config` on the Coder host. Set `use_kubeconfig = true`.

## Configuration

### Template Variables

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `use_kubeconfig` | bool | `false` | Use host kubeconfig for authentication |
| `namespace` | string | required | Kubernetes namespace for workspaces |

### Workspace Parameters

Users can customize these settings when creating a workspace:

| Parameter | Options | Default | Description |
|-----------|---------|---------|-------------|
| CPU | 2, 4, 6, 8 cores | 2 | CPU cores allocated to the workspace |
| Memory | 2, 4, 6, 8 GB | 2 | Memory allocated to the workspace |
| Home Disk Size | 1-99999 GB | 10 | Persistent storage for `/home/coder` |

## Architecture

This template provisions the following Kubernetes resources:

- **Deployment**: A single-replica deployment running the workspace container
- **Persistent Volume Claim**: Storage for the `/home/coder` directory

### Container Image

Uses `codercom/enterprise-base:ubuntu` which includes common development tools. To customize:

- Extend the image with additional tools
- Build your own image based on the [enterprise-images repository](https://github.com/coder/enterprise-images)

### Included Applications

| Application | Access | Description |
|-------------|--------|-------------|
| Claude Code | Subdomain | AI coding assistant with AI Bridge enabled |
| code-server | Subdomain | Browser-based VS Code |

### Workspace Metadata

The dashboard displays real-time metrics:

- CPU Usage (container and host)
- RAM Usage (container and host)
- Home Disk Usage
- Load Average (host)

## Pod Scheduling

Workspaces use pod anti-affinity to distribute pods across nodes, improving cluster utilization and resilience.

## Security

- Containers run as non-root user (UID 1000)
- File system group set to 1000
- Resource limits enforced based on user-selected parameters

## Customization

This template is designed as a starting point. Common modifications include:

- Adding environment variables
- Mounting secrets or configmaps
- Changing the container image
- Adding init containers
- Configuring node selectors or tolerations
