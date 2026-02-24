data "aws_iam_policy_document" "ext-prov" {
  statement {
    effect = "Allow"
    actions = [
      "ec2:GetDefaultCreditSpecification",
      "ec2:DescribeIamInstanceProfileAssociations",
      "ec2:DescribeTags",
      "ec2:DescribeInstances",
      "ec2:DescribeInstanceTypes",
      "ec2:DescribeInstanceStatus",
      "ec2:CreateTags",
      "ec2:RunInstances",
      "ec2:DescribeInstanceCreditSpecifications",
      "ec2:DescribeImages",
      "ec2:ModifyDefaultCreditSpecification",
      "ec2:DescribeVolumes"
    ]
    resources = ["*"]
  }

  statement {
    effect = "Allow"
    actions = [
      "ec2:DescribeInstanceAttribute",
      "ec2:UnmonitorInstances",
      "ec2:TerminateInstances",
      "ec2:StartInstances",
      "ec2:StopInstances",
      "ec2:DeleteTags",
      "ec2:MonitorInstances",
      "ec2:CreateTags",
      "ec2:RunInstances",
      "ec2:ModifyInstanceAttribute",
      "ec2:ModifyInstanceCreditSpecification"
    ]
    resources = ["arn:aws:ec2:*:*:instance/*"]
  }
}