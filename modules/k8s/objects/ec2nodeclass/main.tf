terraform {}

variable "name" {
  type = string
}

variable "ami_alias" {
  type    = string
  default = "al2023@latest"
}

variable "node_role_name" {
  type = string
}

variable "subnet_selector_tags" {
  type    = map(string)
  default = {}
}

variable "sg_selector_tags" {
  type    = map(string)
  default = {}
}

variable "block_device_mappings" {
  type = list(object({
    device_name = string
    ebs = object({
      volume_size           = number # Changed from string to number because AWS EBS volume sizes are numeric GiB values
      volume_type           = string
      encrypted             = optional(bool, false)
      delete_on_termination = optional(bool, true)
    })
  }))
  default = []
}

locals {
  block_device_mappings = [
    for v in var.block_device_mappings : {
      deviceName = v.device_name
      ebs = {
        volumeSize          = v.ebs.volume_size
        volumeType          = v.ebs.volume_type
        encrypted           = v.ebs.encrypted
        deleteOnTermination = v.ebs.delete_on_termination
      }
    }
  ]
}

output "manifest" {
  value = yamlencode({
    apiVersion = "karpenter.k8s.aws/v1"
    kind       = "EC2NodeClass"
    metadata = {
      name = var.name
    }
    spec = {
      role = var.node_role_name
      amiSelectorTerms = [{
        alias = var.ami_alias
      }]
      subnetSelectorTerms = [{
        tags = var.subnet_selector_tags
      }]
      securityGroupSelectorTerms = [{
        tags = var.sg_selector_tags
      }]
      blockDeviceMappings = local.block_device_mappings
    }
  })
}