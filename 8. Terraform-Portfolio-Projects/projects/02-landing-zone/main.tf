data "aws_organizations_organization" "existing" {}
variable "sandbox_account_id" {
  type = string
  validation {
    condition     = can(regex("^[0-9]{12}$", var.sandbox_account_id)) && var.sandbox_account_id != var.account_id
    error_message = "Use a distinct, approved member sandbox account."
  }
}
resource "aws_organizations_organizational_unit" "sandbox" {
  name      = "${var.name}-sandbox"
  parent_id = data.aws_organizations_organization.existing.roots[0].id
}
resource "aws_organizations_policy" "guardrail" {
  name    = "${var.name}-protect-logging"
  type    = "SERVICE_CONTROL_POLICY"
  content = jsonencode({ Version = "2012-10-17", Statement = [{ Sid = "ProtectCloudTrail", Effect = "Deny", Action = ["cloudtrail:StopLogging", "cloudtrail:DeleteTrail"], Resource = "*" }] })
}
resource "aws_organizations_policy_attachment" "sandbox_only" {
  policy_id = aws_organizations_policy.guardrail.id
  target_id = var.sandbox_account_id
}
output "sandbox_ou_id" { value = aws_organizations_organizational_unit.sandbox.id }
output "guardrail_id" { value = aws_organizations_policy.guardrail.id }

resource "aws_organizations_organizational_unit" "core" {
  for_each  = toset(["security", "logging", "shared", "development", "staging", "production"])
  name      = "${var.name}-${each.key}"
  parent_id = data.aws_organizations_organization.existing.roots[0].id
}
output "ou_ids" {
  value = merge({ for name, ou in aws_organizations_organizational_unit.core : name => ou.id }, { sandbox = aws_organizations_organizational_unit.sandbox.id })
}
