variable "repository" { type = string }
variable "oidc_provider_arn" { type = string }
variable "ecr_repository_arn" { type = string }
resource "aws_iam_role" "build" {
  name               = "${var.name}-build"
  assume_role_policy = jsonencode({ Version = "2012-10-17", Statement = [{ Effect = "Allow", Principal = { Federated = var.oidc_provider_arn }, Action = "sts:AssumeRoleWithWebIdentity", Condition = { StringEquals = { "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com", "token.actions.githubusercontent.com:sub" = "repo:${var.repository}:ref:refs/heads/main" } } }] })
}
resource "aws_iam_role_policy" "build" {
  role   = aws_iam_role.build.id
  policy = jsonencode({ Version = "2012-10-17", Statement = [{ Effect = "Allow", Action = "ecr:GetAuthorizationToken", Resource = "*" }, { Effect = "Allow", Action = ["ecr:BatchCheckLayerAvailability", "ecr:InitiateLayerUpload", "ecr:UploadLayerPart", "ecr:CompleteLayerUpload", "ecr:PutImage", "ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer"], Resource = var.ecr_repository_arn }] })
}
# Promotion uses a separate protected GitOps PR identity, not the build role.
output "build_role_arn" { value = aws_iam_role.build.arn }

resource "aws_iam_role" "verify" {
  name               = "${var.name}-verify"
  assume_role_policy = aws_iam_role.build.assume_role_policy
}
resource "aws_iam_role_policy" "verify" {
  role   = aws_iam_role.verify.id
  policy = jsonencode({ Version = "2012-10-17", Statement = [{ Effect = "Allow", Action = "ecr:GetAuthorizationToken", Resource = "*" }, { Effect = "Allow", Action = ["ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer"], Resource = var.ecr_repository_arn }] })
}
resource "aws_iam_role" "promotion" {
  name               = "${var.name}-promotion"
  assume_role_policy = jsonencode({ Version = "2012-10-17", Statement = [{ Effect = "Allow", Principal = { Federated = var.oidc_provider_arn }, Action = "sts:AssumeRoleWithWebIdentity", Condition = { StringEquals = { "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com", "token.actions.githubusercontent.com:sub" = "repo:${var.repository}:environment:production-promotion" } } }] })
}
output "verify_role_arn" { value = aws_iam_role.verify.arn }
output "promotion_role_arn" { value = aws_iam_role.promotion.arn }
