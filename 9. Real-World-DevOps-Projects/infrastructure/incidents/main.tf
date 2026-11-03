resource "aws_iam_role" "execution" {
  name               = "${var.name}-diagnostic"
  assume_role_policy = jsonencode({ Version = "2012-10-17", Statement = [{ Effect = "Allow", Principal = { Service = "ssm.amazonaws.com" }, Action = "sts:AssumeRole", Condition = { StringEquals = { "aws:SourceAccount" = var.account_id }, ArnLike = { "aws:SourceArn" = "arn:aws:ssm:${var.region}:${var.account_id}:automation-execution/*" } } }] })
}
resource "aws_iam_role_policy" "execution" {
  role   = aws_iam_role.execution.id
  policy = jsonencode({ Version = "2012-10-17", Statement = [{ Effect = "Allow", Action = "rds:DescribeDBInstances", Resource = "*" }] })
}
resource "aws_ssm_document" "diagnose" {
  name            = "veriqta-diagnose-database"
  document_type   = "Automation"
  document_format = "YAML"
  content         = file("${path.module}/../../projects/10-incident-command/diagnose-database.yaml")
}
output "execution_role_arn" { value = aws_iam_role.execution.arn }
output "document_arn" { value = aws_ssm_document.diagnose.arn }
