import {
    to = aws_eks_access_entry.runner
    identity = {
        cluster_name  = module.eks.cluster_name
        principal_arn = "arn:aws:iam::${data.aws_caller_identity.me.account_id}:role/tf-runner-role"
    }
}

import {
  to = aws_eks_access_policy_association.runner
  identity = {
    cluster_name  = module.eks.cluster_name
    principal_arn = "arn:aws:iam::${data.aws_caller_identity.me.account_id}:role/tf-runner-role"
    policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  }
}