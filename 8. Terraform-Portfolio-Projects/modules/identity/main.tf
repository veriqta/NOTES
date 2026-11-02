variable "name" { type = string }
variable "trusted_role_arns" { type = set(string) }
variable "permissions" { type = string }
resource "aws_iam_role" "this" {
  name = var.name
  assume_role_policy = jsonencode({ Version = "2012-10-17", Statement = [{ Effect = "Allow", Action = "sts:AssumeRole", Principal = { AWS = sort(tolist(var.trusted_role_arns)) }
  }] })
}
resource "aws_iam_role_policy" "workload" {
  role   = aws_iam_role.this.id
  policy = var.permissions
}
output "role_arn" { value = aws_iam_role.this.arn }
