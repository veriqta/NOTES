variable "database_arn" { type = string }
variable "source_vault_name" { type = string }
variable "destination_vault_arn" { type = string }
variable "key_arns" { type = set(string) }
resource "aws_iam_role" "backup" {
  name               = "${var.name}-backup"
  assume_role_policy = jsonencode({ Version = "2012-10-17", Statement = [{ Effect = "Allow", Principal = { Service = "backup.amazonaws.com" }, Action = "sts:AssumeRole" }] })
}
resource "aws_iam_role_policy_attachment" "backup" {
  role       = aws_iam_role.backup.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup"
}
resource "aws_iam_role_policy" "keys" {
  role   = aws_iam_role.backup.id
  policy = jsonencode({ Version = "2012-10-17", Statement = [{ Effect = "Allow", Action = ["kms:Decrypt", "kms:Encrypt", "kms:GenerateDataKey*", "kms:DescribeKey", "kms:CreateGrant"], Resource = sort(tolist(var.key_arns)) }] })
}
resource "aws_backup_plan" "this" {
  name = var.name
  rule {
    rule_name         = "daily-copy"
    target_vault_name = var.source_vault_name
    schedule          = "cron(0 3 * * ? *)"
    lifecycle { delete_after = 14 }
    copy_action {
      destination_vault_arn = var.destination_vault_arn
      lifecycle { delete_after = 30 }
    }
  }
}
resource "aws_backup_selection" "this" {
  name         = var.name
  plan_id      = aws_backup_plan.this.id
  iam_role_arn = aws_iam_role.backup.arn
  resources    = [var.database_arn]
  depends_on   = [aws_iam_role_policy_attachment.backup, aws_iam_role_policy.keys]
}
output "backup_role_arn" { value = aws_iam_role.backup.arn }
