# Coder Demo Environment (coderdemo.io)

Welcome to the Coder Demo Environment's Github repository!

This project powers ["coderdemo.io"](https://coderdemo.io), a demonstration environment showcasing Coder's cloud development capabilities and features.

---

## Getting Started

### Accessing the Deployment:

Get Started Here 👉 [https://coderdemo.io](https://coderdemo.io)

**Login Flow**

1. Click "Sign in with GitHub"
2. Authorize the Coder Demo GitHub App
3. Start creating workspaces!

> [!NOTE] This is a demo environment. For production Coder deployments, refer to the [official Coder documentation](https://coder.com/docs).

---

## How-To-Deploy

> [!WARNING] The following environment is heavily opinionated towards: AWS. Make sure to pull the modules and modify according to your use-case. Additionally, the [`infra/aws/us-east-2`](./infra/aws/us-east-2) project is not repeatable. For repeatable references, check out [`infra/aws/us-west-2`](./infra/aws/us-west-2) and [`infra/aws/eu-west-2`](./infra/aws/eu-west-2)

In this repository, we deploy the infrastructure separately from the K8s applications which includes Coder.

To make things easy, we generate K8s app manifests from any `k8s/` project subfolders which reference the main `eks/` application indirectly which auto-populates any infrastructure dependent resource names.

### About the Infrastructure

The deployment currently has 2 repeatable components: [`eks-vpc` module](./modules/network/eks-vpc) and [`eks-cluster` module](./modules/compute/cluster).

#### [`eks-vpc`](./modules/network/eks-vpc)

The following module creates an opinionated VPC that let's you granularly define individual subnets. This includes unevenly defining public and private subnets.

This will come with an Internet Gateway and a Custom NAT Gateway (using [RaJiska/terraform-aws-fck-nat](github.com/RaJiska/terraform-aws-fck-nat)).

The public subnets will have automatic routes to the IGW and private subnets with routes to the NAT.

#### [`eks-cluster`](./modules/compute/cluster).

The following module creates an opinionated cluster, similar to [EKS Auto Mode](https://docs.aws.amazon.com/eks/latest/userguide/automode.html), that creates both the EKS Cluster (using the [AWS Managed Terraform EKS module](https://github.com/terraform-aws-modules/terraform-aws-eks/tree/master)), and resources needed by:

- [Karpenter](https://karpenter.sh/)
- [Amazon Bedrock](https://docs.aws.amazon.com/bedrock/latest/userguide/what-is-bedrock.html)
- [AWS EBS Controller](https://github.com/kubernetes-sigs/aws-ebs-csi-driver)
- [AWS Load Balancer Controller](https://github.com/kubernetes-sigs/aws-load-balancer-controller)
- [Coder External Provisioner](https://coder.com/docs/admin/provisioners)

##### Karpenter

We use the the [AWS Managed Terraform EKS Module for Karpenter in the background](https://github.com/terraform-aws-modules/terraform-aws-eks/tree/master/modules/karpenter).

This automatically creates:

- SQS Queue
- IAM Roles
- Event Bridge

##### Amazon Bedrock

Auto-Creates

- IAM Role

##### AWS EBS Controller

Auto-Creates

- IAM Role

##### AWS Load Balancer Controller

Auto-Creates

- IAM Role

##### Coder External Provisioner

Auto-Creates

- IAM Role

### Creating the Infrastructure (on AWS)

To deploy the base infrastructure, you can get started with referencing our [modules directory](./modules).

If you don't have an existing network infrastructure, then you can start with deploying the [`eks-vpc` module](./modules/network/eks-vpc).

Additionally, if you don't have an existing cluster infrastructure, then you can start with deploying the [`eks-cluster` module](./modules/compute/cluster).

Lastly, for Coder's backend database, you can refer to our deployment in [`./infra/aws/us-east-2/rds`](./infra/aws/us-east-2/rds) to see how to deploy it.

We just an [`aws_db_instance`](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/db_instance) that uses Postgres.

Refer to the example below to see how this would look like put together:

```terraform

terraform {
    required_version = ">= 1.0"
    required_providers {
        aws = {
            source  = "hashicorp/aws"
            version = ">= 5.100.0"
        }
    }
}

variable "name" {
    description = "The resource name."
    type        = string
}

variable "region" {
    description = "The aws region to deploy eks cluster"
    type        = string
}

variable "cluster_version" {
    description = "The EKS Version"
    type        = string
}

variable "cluster_instance_type" {
    description = "EKS Instance Size/Type."
    default     = "t3.xlarge"
    type        = string
}

variable "coder_ws_volume_size" {
    description = "Coder Workspace K8s Node Volume Size."
    default     = 50
    type        = number
}

variable "coder_ws_instance_type" {
    description = "Coder Workspace K8s Node Instance Size/Type."
    default     = "t3.xlarge"
    type        = string
}

variable "network_cidr_block" {
    description = "VPC CIDR Block"
    type = string
    default = "10.0.0.0/16"
}

variable "db_instance_class" {
    description = "RDS DB Instance Class"
    type = string
    default = "db.m5.large"
}

variable "db_allocated_storage" {
    description = "RDS DB Allocated Storage Amount"
    type = string
    default = "40"
}

variable "db_master_username" {
    description = "RDS DB Master Username"
    type = string
    sensitive = true
}

variable "db_master_password" {
    description = "RDS DB Master Password"
    type = string
    sensitive = true
}

module "eks-network" {
    source = "../../../../modules/network/eks-vpc"

    name = var.name
    vpc_cidr_block = var.network_cidr_block
    public_subnets = {
        # System subnets requiring public access (e.g. NAT Gateways, Load Balancers, IGW, etc.)
        "system0" = {
            cidr_block = "10.0.10.0/24"
            availability_zone = "${data.aws_region.this.name}a"
            map_public_ip_on_launch = true
            private_dns_hostname_type_on_launch = "ip-name"
        }
        "system1" = {
            cidr_block = "10.0.11.0/24"
            availability_zone = "${data.aws_region.this.name}b"
            map_public_ip_on_launch = true
            private_dns_hostname_type_on_launch = "ip-name"
        }
    }
    private_subnets = {
        # System subnets that don't need to be exposed publically (e.g. K8s Worker Nodes, Database, etc.)
        "system0" = {
            cidr_block = "10.0.20.0/24"
            availability_zone = "${data.aws_region.this.name}a"
            private_dns_hostname_type_on_launch = "ip-name"
            tags = local.system_subnet_tags
        }
        "system1" = {
            cidr_block = "10.0.21.0/24"
            availability_zone = "${data.aws_region.this.name}b"
            private_dns_hostname_type_on_launch = "ip-name"
            tags = local.system_subnet_tags
        }
        "provisioner" = {
            cidr_block = "10.0.22.0/24"
            availability_zone = "${data.aws_region.this.name}a"
            map_public_ip_on_launch = true
            private_dns_hostname_type_on_launch = "ip-name"
            tags = local.provisioner_subnet_tags
        }
        "ws-all" = {
            cidr_block = "10.0.16.0/22"
            availability_zone = "${data.aws_region.this.name}b"
            map_public_ip_on_launch = true
            private_dns_hostname_type_on_launch = "ip-name"
            tags = local.ws_all_subnet_tags
        }
    }
}

data "aws_iam_policy_document" "sts" {
    statement {
        effect = "Allow"
        actions = ["sts:*"]
        resources = ["*"]
    }
}

resource "aws_iam_policy" "sts" {
    name_prefix = "sts"
    path = "/"
    description = "Assume Role Policy"
    policy = data.aws_iam_policy_document.sts.json
}

module "eks-cluster" {
    source = "../../../../modules/compute/cluster"

    vpc_id     = module.eks-network.vpc_id
    cluster_public_subnet_ids = module.eks-network.public_subnet_ids
    cluster_private_subnet_ids = module.eks-network.private_subnet_ids
    cluster_intra_subnet_ids = module.eks-network.intra_subnet_ids
    cluster_instance_type = var.cluster_instance_type

    cluster_name                    = var.name
    cluster_version                 = var.cluster_version
    cluster_asg_additional_policies = {
        AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
        STSAssumeRole = aws_iam_policy.sts.arn
    }
    cluster_node_security_group_tags = merge(
        local.system_sg_tags,
        merge(local.provisioner_sg_tags, local.ws_all_sg_tags)
    )
    cluster_asg_node_labels = local.cluster_asg_node_labels
    cluster_addons = {
        coredns = {
            most_recent = true
        }
        kube-proxy = {
            most_recent = true
        }
        vpc-cni = {
            most_recent = true
        }
    }

    karpenter_controller_policy_statements = [{
      effect = "Allow",
      actions = toset(["iam:PassRole"]),
      resources = toset(["*"]),
    }]

    karpenter_node_role_policies = {
        AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
        STSAssumeRole = aws_iam_policy.sts.arn
    }

    coder_ws_instance_type = var.coder_ws_instance_type
    coder_ws_volume_size = var.coder_ws_volume_size
}

###
# Only deploy the database if you're creating the central Coder infrastructure.
# Otherwise, if you're deploying separate clusters for Coder proxies + provisioners in a different network, then there's no need for another database.
###

resource "aws_db_subnet_group" "db_subnet_group" {
  name       = "${var.name}-db-subnet-group"
  subnet_ids = module.eks-network.private_subnet_ids

  tags = {
    Name = "${var.name}-db-subnet-group"
  }
}

resource "aws_db_instance" "db" {
  identifier        = "${var.name}-db"
  instance_class    = var.instance_class
  allocated_storage = var.allocated_storage
  engine            = "postgres"
  engine_version    = "15.12"
  username               = var.master_username
  password               = var.master_password
  db_name                = "coder"
  db_subnet_group_name   = aws_db_subnet_group.db_subnet_group.name
  vpc_security_group_ids = [ aws_security_group.postgres.id ]
  publicly_accessible = false
  skip_final_snapshot = false

  tags = {
    Name = "${var.name}-rds-db"
  }
  lifecycle {
    ignore_changes = [
      snapshot_identifier
    ]
  }
}

resource "aws_vpc_security_group_ingress_rule" "postgres" {
  security_group_id = aws_security_group.postgres.id
  cidr_ipv4 = var.network_cidr_block
  ip_protocol = "tcp"
  from_port = 5432
  to_port = 5432
}

resource "aws_vpc_security_group_egress_rule" "all" {
  security_group_id = aws_security_group.postgres.id
  cidr_ipv4 = "0.0.0.0/0"
  ip_protocol = -1
}

resource "aws_security_group" "postgres" {
  vpc_id      = module.eks-network.vpc_id
  name        = "${var.name}-postgres"
  description = "Security Group for Postgres traffic"
  tags = {
    Name = "${var.name}-postgres"
  }
}
```

The deployment may take a while (~20 minutes or more). In the meantime, you can then get started with creating other dependencies.

### Deploying Required Apps

Once the K8s (and maybe the Database) infrastructure is deployed, the next step is to deploy the K8s apps.

Before getting to Coder, we should first deploy:

- [`AWS Load Balancer Controller`](https://github.com/kubernetes-sigs/aws-load-balancer-controller)
- [`AWS EBS Controller`](https://github.com/kubernetes-sigs/aws-ebs-csi-driver)
- [`K8s Metrics Server`](github.com/kubernetes-sigs/metrics-server)
- [`Karpenter`](https://karpenter.sh/docs/getting-started/getting-started-with-karpenter/#4-install-karpenter)
- [`Cert-Manager`](https://cert-manager.io/docs/installation/helm/)

Afterwards, you can then deploy

- [`Coder Server`](https://artifacthub.io/packages/helm/coder-v2/coder)
- [`Coder Proxy` (uses same chart as the Coder Server)](https://artifacthub.io/packages/helm/coder-v2/coder)
- [`Coder Workspace`](https://artifacthub.io/packages/helm/coder-v2/coder-provisioner)

You can deploy the above manually yourself following your own preferred methods.

Otherwise, you can leverage our K8s app TF modules to automatically generate the manifests:

#### [`lb-controller`](./modules/k8s/apps/lb-controller)

#### [`ebs-controller`](./modules/k8s/apps/ebs-controller)

#### [`metrics-server`](./modules/k8s/apps/metrics-server)

#### [`karpenter`](./modules/k8s/apps/karpenter)

#### [`cert-manager`](./modules/k8s/apps/cert-manager)

#### [`coder-server`](./modules/k8s/apps/coder-server)

#### [`coder-proxy`](./modules/k8s/apps/coder-proxy)

#### [`coder-ws`](./modules/k8s/apps/coder-ws)

## How-It-Works

> <!TODO>

### Coder Tasks

> <!TODO>
