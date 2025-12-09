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
      "ec2:DescribeInstanceAttribute",
      "ec2:MonitorInstances"
    ]
    resources = [
      "arn:aws:ec2:${local.region}:${local.account_id}:*",
      "arn:aws:ec2:${local.region}:${local.account_id}:*/*",
      "arn:aws:ec2:${local.region}:${local.account_id}:*:*",
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
      "arn:aws:ec2:${local.region}:${local.account_id}:*",
      "arn:aws:ec2:${local.region}:${local.account_id}:*/*",
      "arn:aws:ec2:${local.region}:${local.account_id}:*:*",
      "arn:aws:ec2:${local.region}::image/*"
    ]
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
    resources = ["*"]
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
    actions = [
      "iam:Get*",
      "iam:List*"
    ]
    resources = ["arn:aws:iam::${local.account_id}:*"]
  }

  statement {
    sid    = "IAMPassRole"
    effect = "Allow"
    actions = [
      "iam:PassRole",
    ]
    resources = ["arn:aws:iam::${local.account_id}:*"]
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
    resources = [
      "arn:aws:bedrock:*:*:*",
      "arn:aws:bedrock:*:*:*/*",
      "arn:aws:bedrock:*:*:*:*",
    ]
  }
}