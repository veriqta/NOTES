variable "repository" {
  type        = string
  description = "Exact GitHub owner/repository."
  validation {
    condition     = can(regex("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$", var.repository))
    error_message = "Use owner/repository without wildcards."
  }
}
variable "oidc_provider_arn" { type = string }
variable "state_bucket_arn" { type = string }
variable "state_kms_key_arn" { type = string }
variable "state_key" {
  type    = string
  default = "environments/dev/terraform.tfstate"
}
variable "workload_apply_policy_json" {
  type = string
  validation {
    condition     = can(jsondecode(var.workload_apply_policy_json).Statement)
    error_message = "Supply reviewed workload-specific IAM policy JSON."
  }
}
resource "aws_iam_role" "pipeline" {
  for_each             = toset(["plan", "apply"])
  name                 = "${var.name}-${each.key}"
  max_session_duration = 3600
  assume_role_policy = jsonencode({ Version = "2012-10-17", Statement = [{ Effect = "Allow", Action = "sts:AssumeRoleWithWebIdentity", Principal = { Federated = var.oidc_provider_arn }, Condition = { StringEquals = {
    "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com",
    "token.actions.githubusercontent.com:sub" = each.key == "plan" ? "repo:${var.repository}:ref:refs/heads/main" : "repo:${var.repository}:environment:terraform-production"
    }
  } }] })
}
resource "aws_iam_role_policy" "backend" {
  for_each = aws_iam_role.pipeline
  role     = each.value.id
  policy = jsonencode({ Version = "2012-10-17", Statement = [
    { Effect = "Allow", Action = "s3:ListBucket", Resource = var.state_bucket_arn, Condition = { StringLike = { "s3:prefix" = [var.state_key, "${var.state_key}.tflock", "environments/${var.environment}/workspaces/*", "environments/${var.environment}/workspaces/"] }
    } },
    { Effect = "Allow", Action = each.key == "apply" ? ["s3:GetObject", "s3:PutObject"] : ["s3:GetObject"], Resource = "${var.state_bucket_arn}/${var.state_key}" },
    { Effect = "Allow", Action = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"], Resource = "${var.state_bucket_arn}/${var.state_key}.tflock" },
    { Effect = "Allow", Action = ["kms:Decrypt", "kms:Encrypt", "kms:GenerateDataKey"], Resource = var.state_kms_key_arn, Condition = { StringEquals = { "kms:ViaService" = "s3.${var.region}.amazonaws.com" }
    } }
  ] })
}
resource "aws_iam_role_policy" "read_workload" {
  for_each = aws_iam_role.pipeline
  role     = each.value.id
  policy   = jsonencode({ Version = "2012-10-17", Statement = [{ Effect = "Allow", Action = ["ec2:Describe*"], Resource = "*" }] })
}
resource "aws_iam_role_policy" "apply_workload" {
  role   = aws_iam_role.pipeline["apply"].id
  policy = var.workload_apply_policy_json
}
output "role_arns" {
  value = { for k, v in aws_iam_role.pipeline : k => v.arn }
}
