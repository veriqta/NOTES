variable "approved_parent_ou_id" { type = string }
variable "accounts" {
  type        = map(object({ email = string }))
  default     = {}
  description = "Optional new accounts; each needs a unique operator-owned email address."
}
resource "aws_organizations_account" "this" {
  for_each          = var.accounts
  name              = each.key
  email             = each.value.email
  parent_id         = var.approved_parent_ou_id
  role_name         = "VeriqtaAccountBootstrap"
  close_on_deletion = false
  lifecycle { prevent_destroy = true }
}
output "account_ids" {
  value = { for k, v in aws_organizations_account.this : k => v.id }
}
