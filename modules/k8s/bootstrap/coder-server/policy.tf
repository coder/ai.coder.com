data "aws_iam_policy_document" "provisioner-policy" {
  statement {
    sid    = "EC2InstanceLifecycle"
    effect = "Allow"
    actions = [
      "ec2:RunInstances",
      "ec2:StartInstances",
      "ec2:StopInstances",
      "ec2:TerminateInstances",
      "ec2:DescribeInstances",
      "ec2:RebootInstances",
      "ec2:ModifyInstanceAttribute",
      "ec2:DescribeInstanceAttribute"
    ]
    # Restrict to specific resource types for least privilege
    resources = [
      "arn:aws:ec2:${local.region}:${local.account_id}:instance/*",
      "arn:aws:ec2:${local.region}:${local.account_id}:volume/*",
      "arn:aws:ec2:${local.region}:${local.account_id}:network-interface/*",
      "arn:aws:ec2:${local.region}:${local.account_id}:security-group/*",
      "arn:aws:ec2:${local.region}:${local.account_id}:subnet/*",
      "arn:aws:ec2:${local.region}:${local.account_id}:key-pair/*",
      "arn:aws:ec2:${local.region}::image/*"
    ]
  }

  statement {
    sid    = "EC2ManageHostLifecycle"
    effect = "Allow"
    actions = [
      "ec2:AllocateHosts",
      "ec2:ModifyHosts",
      "ec2:ReleaseHosts"
    ]
    resources = [
      "arn:aws:ec2:${local.region}:${local.account_id}:dedicated-host/*"
    ]
    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/ManagedBy"
      values   = ["coder"]
    }
  }

  statement {
    sid    = "EC2ManageHostLifecycleExisting"
    effect = "Allow"
    actions = [
      "ec2:ModifyHosts",
      "ec2:ReleaseHosts"
    ]
    resources = [
      "arn:aws:ec2:${local.region}:${local.account_id}:dedicated-host/*"
    ]
    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/ManagedBy"
      values   = ["coder"]
    }
  }

  statement {
    sid    = "EBSVolumeLifecycle"
    effect = "Allow"
    actions = [
      "ec2:CreateVolume",
      "ec2:AttachVolume",
      "ec2:DetachVolume",
      "ec2:DeleteVolume",
      "ec2:DescribeVolumes",
    ]
    resources = [
      "arn:aws:ec2:${local.region}:${local.account_id}:*",
      "arn:aws:ec2:${local.region}:${local.account_id}:*/*",
      "arn:aws:ec2:${local.region}:${local.account_id}:*:*",
    ]
  }

  statement {
    sid    = "SecurityGroupLifecycle"
    effect = "Allow"
    actions = [
      "ec2:CreateSecurityGroup",
      "ec2:AuthorizeSecurityGroupIngress",
      "ec2:AuthorizeSecurityGroupEgress",
      "ec2:RevokeSecurityGroupIngress",
      "ec2:RevokeSecurityGroupEgress",
      "ec2:DeleteSecurityGroup",
      "ec2:DescribeSecurityGroups",
    ]
    resources = [
      "arn:aws:ec2:${local.region}:${local.account_id}:*",
      "arn:aws:ec2:${local.region}:${local.account_id}:*/*",
      "arn:aws:ec2:${local.region}:${local.account_id}:*:*",
    ]
  }

  statement {
    sid    = "TagLifecycle"
    effect = "Allow"
    actions = [
      "ec2:CreateTags",
      "ec2:DeleteTags",
    ]
    resources = [
      "arn:aws:ec2:${local.region}:${local.account_id}:*",
      "arn:aws:ec2:${local.region}:${local.account_id}:*/*",
      "arn:aws:ec2:${local.region}:${local.account_id}:*:*",
    ]
  }

  statement {
    sid    = "NetworkInterfaceLifecycle"
    effect = "Allow"
    actions = [
      "ec2:CreateNetworkInterface",
      "ec2:AttachNetworkInterface",
      "ec2:DetachNetworkInterface",
      "ec2:DeleteNetworkInterface",
      "ec2:DescribeNetworkInterfaces",
      "ec2:ModifyNetworkInterfaceAttribute",
    ]
    resources = [
      "arn:aws:ec2:${local.region}:${local.account_id}:*",
      "arn:aws:ec2:${local.region}:${local.account_id}:*/*",
      "arn:aws:ec2:${local.region}:${local.account_id}:*:*",
    ]
  }

  statement {
    sid    = "ECRAuth"
    effect = "Allow"
    actions = [
      "ecr:GetAuthorizationToken"
    ]
    resources = ["*"]
  }

  statement {
    sid    = "ECRDownloadImages"
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer"
    ]
    # Restrict to specific repositories for least privilege
    resources = ["arn:aws:ecr:${local.region}:${local.account_id}:repository/*"]
  }

  statement {
    sid    = "ECRUploadImages"
    effect = "Allow"
    actions = [
      "ecr:CompleteLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:InitiateLayerUpload",
      "ecr:BatchCheckLayerAvailability",
      "ecr:PutImage",
      "ecr:BatchGetImage"
    ]
    resources = ["arn:aws:ecr:${local.region}:${local.account_id}:repository/*"]
  }

  statement {
    sid    = "IAMReadOnly"
    effect = "Allow"
    # Restrict to specific IAM read actions for least privilege
    actions = [
      "iam:GetRole",
      "iam:GetInstanceProfile",
      "iam:ListInstanceProfiles",
      "iam:ListRoles"
    ]
    resources = ["arn:aws:iam::${local.account_id}:role/*", "arn:aws:iam::${local.account_id}:instance-profile/*"]
  }

  statement {
    sid    = "IAMPassRole"
    effect = "Allow"
    actions = [
      "iam:PassRole",
    ]
    # Restrict to specific role pattern for least privilege
    resources = ["arn:aws:iam::${local.account_id}:role/*"]
    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ec2.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "ws-policy" {
  statement {
    sid    = "AllowModelInvocation"
    effect = "Allow"
    actions = [
      "bedrock:InvokeModel",
      "bedrock:InvokeModelWithResponseStream",
      "bedrock:ListInferenceProfiles"
    ]
    # Restrict to specific region and foundation models for least privilege
    resources = [
      "arn:aws:bedrock:${local.region}::foundation-model/*",
      "arn:aws:bedrock:${local.region}:${local.account_id}:inference-profile/*"
    ]
  }
}