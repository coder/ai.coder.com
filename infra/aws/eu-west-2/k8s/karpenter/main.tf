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
      values   = ["m5a.xlarge", "m6a.xlarge"]
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
      values   = ["m5a.4xlarge", "m6a.4xlarge"]
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
      values   = ["c6a.32xlarge", "c5a.32xlarge"]
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
        volume_size = "500Gi"
        volume_type = "gp3"
      }
      }, {
      device_name = "/dev/xvdb"
      ebs = {
        volume_size = "50Gi"
        volume_type = "gp3"
      }
    }]
    }, {
    name                 = "coder-provisioner-class"
    subnet_selector_tags = local.provisioner_subnet_tags
    sg_selector_tags     = local.provisioner_sg_tags
  }]
}