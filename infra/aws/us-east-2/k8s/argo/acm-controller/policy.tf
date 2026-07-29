# https://github.com/aws-controllers-k8s/acm-controller/blob/603d7dff2c75d36f0b0b4bbdeee7604457a79070/config/iam/recommended-inline-policy
data "aws_iam_policy_document" "this" {
  statement {
    sid    = "ACMPublicCertificatePermissions"
    effect = "Allow"
    actions = [
      "acm:DescribeCertificate",
      "acm:ImportCertificate",
      "acm:RequestCertificate",
      "acm:UpdateCertificateOptions",
      "acm:DeleteCertificate",
      "acm:AddTagsToCertificate",
      "acm:RemoveTagsFromCertificate",
      "acm:ListTagsForCertificate",
      "acm:ExportCertificate"
    ]
    resources = ["*"]
  }

  statement {
    sid    = "ACMPrivateCertificatePermissions"
    effect = "Allow"
    actions = [
      "acm-pca:IssueCertificate",
      "acm-pca:GetCertificate",
      "acm-pca:ListPermissions"
    ]
    resources = ["*"]
  }
}