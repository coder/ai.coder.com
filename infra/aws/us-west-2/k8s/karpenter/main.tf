terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "3.1.1"
    }
    kubernetes = {
      source = "hashicorp/kubernetes"
    }
    null = {
      source = "hashicorp/null"
    }
  }
  backend "s3" {}
}

variable "cluster_name" {
  type = string
}

variable "cluster_oidc_provider_arn" {
  type = string
}

variable "cluster_region" {
  type = string
}

variable "cluster_profile" {
  type    = string
  default = "default"
}

variable "addon_version" {
  type = string
}

variable "addon_namespace" {
  type    = string
  default = "default"
}

variable "karpenter_queue_name" {
  type    = string
  default = ""
}

variable "karpenter_queue_rule_name" {
  type    = string
  default = ""
}

provider "aws" {
  region  = var.cluster_region
  profile = var.cluster_profile
}

data "aws_eks_cluster" "this" {
  name = var.cluster_name
}

data "aws_eks_cluster_auth" "this" {
  name = var.cluster_name
}

provider "helm" {
  kubernetes = {
    host                   = data.aws_eks_cluster.this.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)
    token                  = data.aws_eks_cluster_auth.this.token
  }
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.this.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.this.token
}

locals {
  global_node_labels = {
    "node.coder.io/instance"   = "coder-v2"
    "node.coder.io/managed-by" = "karpenter"
  }
  global_node_reqs = [{
    key      = "kubernetes.io/arch"
    operator = "In"
    values   = ["amd64"]
    }, {
    key      = "kubernetes.io/os"
    operator = "In"
    values   = ["linux"]
    }, {
    key      = "kubernetes.sh/capacity-type"
    operator = "In"
    values   = ["spot", "on-demand"]
  }]
  provisioner_subnet_tags = {
    "subnet.amazonaws.io/coder-provisioner/owned-by" = var.cluster_name
  }
  ws_all_subnet_tags = {
    "subnet.amazonaws.io/coder-ws-all/owned-by" = var.cluster_name
  }
  provisioner_sg_tags = {
    "sg.amazonaws.io/coder-provisioner/owned-by" = var.cluster_name
  }
  ws_all_sg_tags = {
    "sg.amazonaws.io/coder-ws-all/owned-by" = var.cluster_name
  }
}

locals {
  nodepool_configs = [{
    name = "coder-server"
    node_labels = merge(local.global_node_labels, {
      "node.coder.io/name"     = "coder"
      "node.coder.io/part-of"  = "coder"
      "node.coder.io/used-for" = "coder-server"
    })
    node_taints = [{
      key    = "dedicated"
      value  = "coder-server"
      effect = "NoSchedule"
    }]
    node_requirements = concat(local.global_node_reqs, [{
      key      = "node.kubernetes.io/instance-type"
      operator = "In"
      values   = ["t3.xlarge", "t3a.xlarge", "t3.2xlarge", "t3a.2xlarge"]
    }])
    node_class_ref_name = "coder-proxy-class"
    }, {
    name = "coder-proxy"
    node_labels = merge(local.global_node_labels, {
      "node.coder.io/name"     = "coder"
      "node.coder.io/part-of"  = "coder"
      "node.coder.io/used-for" = "coder-proxy"
    })
    node_taints = [{
      key    = "dedicated"
      value  = "coder-proxy"
      effect = "NoSchedule"
    }]
    node_requirements = concat(local.global_node_reqs, [{
      key      = "node.kubernetes.io/instance-type"
      operator = "In"
      values   = ["m5a.xlarge", "m6a.xlarge", "t3.xlarge", "t3a.xlarge"]
    }])
    node_class_ref_name = "coder-proxy-class"
    }, {
    name = "coder-provisioner"
    node_labels = merge(local.global_node_labels, {
      "node.coder.io/name"     = "coder"
      "node.coder.io/part-of"  = "coder"
      "node.coder.io/used-for" = "coder-provisioner"
    })
    node_taints = [{
      key    = "dedicated"
      value  = "coder-provisioner"
      effect = "NoSchedule"
    }]
    node_requirements = concat(local.global_node_reqs, [{
      key      = "node.kubernetes.io/instance-type"
      operator = "In"
      values   = ["m5a.4xlarge", "m6a.4xlarge", "m5a.2xlarge", "m6a.2xlarge"]
    }])
    node_class_ref_name = "coder-provisioner-class"
    }, {
    name = "coder-ws-all"
    node_labels = merge(local.global_node_labels, {
      "node.coder.io/name"     = "coder"
      "node.coder.io/part-of"  = "coder"
      "node.coder.io/used-for" = "coder-ws-all"
    })
    node_taints = [{
      key    = "dedicated"
      value  = "coder-ws"
      effect = "NoSchedule"
    }]
    node_requirements = concat(local.global_node_reqs, [{
      key      = "node.kubernetes.io/instance-type"
      operator = "In"
      values = [
        # Small demos (5-10 users) - Most cost-effective
        "c6a.4xlarge", "c5a.4xlarge", # 16 vCPU / 32 GB  - ~$0.18/hr spot
        "c6a.8xlarge", "c5a.8xlarge", # 32 vCPU / 64 GB  - ~$0.37/hr spot
        # Medium demos (10-20 users)
        "c6a.16xlarge", "c5a.16xlarge", # 64 vCPU / 128 GB - ~$0.74/hr spot
        # Large demos (20-40 users)
        "c6a.32xlarge", "c5a.32xlarge" # 128 vCPU / 256 GB - ~$1.47/hr spot
      ]
    }])
    node_class_ref_name          = "coder-ws-class"
    disruption_consolidate_after = "30m"
  }]
}

module "karpenter-addon" {
  source                    = "../../../../../modules/k8s/bootstrap/karpenter"
  cluster_name              = var.cluster_name
  cluster_oidc_provider_arn = var.cluster_oidc_provider_arn

  namespace     = var.addon_namespace
  chart_version = var.addon_version
  node_selector = {
    "node.amazonaws.io/managed-by" : "asg"
  }

  karpenter_queue_name      = var.karpenter_queue_name
  karpenter_queue_rule_name = var.karpenter_queue_rule_name
  ec2nodeclass_configs = [{
    name                 = "coder-proxy-class"
    subnet_selector_tags = local.provisioner_subnet_tags
    sg_selector_tags     = local.provisioner_sg_tags
    }, {
    name                 = "coder-ws-class"
    subnet_selector_tags = local.ws_all_subnet_tags
    # ami_alias = "al2023@latest" # Use /dev/xvda
    ami_alias        = "bottlerocket@latest" # Use /dev/xvda + /dev/xvdb
    sg_selector_tags = local.ws_all_sg_tags
    block_device_mappings = [{
      device_name = "/dev/xvda"
      ebs = {
        volume_size = "500G"
        volume_type = "gp3"
      }
      }, {
      device_name = "/dev/xvdb"
      ebs = {
        volume_size = "50G"
        volume_type = "gp3"
      }
    }]
    }, {
    name                 = "coder-provisioner-class"
    subnet_selector_tags = local.provisioner_subnet_tags
    sg_selector_tags     = local.provisioner_sg_tags
  }]
}

# Create NodePools for each configuration
module "nodepools" {
  for_each = { for np in local.nodepool_configs : np.name => np }
  source   = "../../../../../modules/k8s/objects/nodepool"

  name                            = each.value.name
  node_labels                     = each.value.node_labels
  node_taints                     = each.value.node_taints
  node_requirements               = each.value.node_requirements
  node_class_ref_name             = each.value.node_class_ref_name
  disruption_consolidate_after    = lookup(each.value, "disruption_consolidate_after", "1m")
  disruption_consolidation_policy = lookup(each.value, "disruption_consolidation_policy", "WhenEmpty")

  depends_on = [module.karpenter-addon]
}

# Apply the NodePool manifests
resource "null_resource" "apply_nodepools" {
  for_each = module.nodepools

  provisioner "local-exec" {
    command = "echo '${each.value.manifest}' | kubectl apply -f -"
  }

  depends_on = [module.karpenter-addon]
}