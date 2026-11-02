variable "trusted_deployment_role_arns" { type = set(string) }
variable "deployment_permissions" {
  type        = string
  description = "Reviewed workload-specific IAM policy JSON, not AdministratorAccess."
}
module "deployment_identity" {
  source            = "../../../modules/identity"
  name              = "${var.name}-deployment"
  trusted_role_arns = var.trusted_deployment_role_arns
  permissions       = var.deployment_permissions
}
resource "aws_guardduty_detector" "this" { enable = true }
resource "aws_securityhub_account" "this" {}
resource "aws_ebs_encryption_by_default" "this" { enabled = true }
resource "aws_s3_account_public_access_block" "this" {
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
output "deployment_role_arn" { value = module.deployment_identity.role_arn }
