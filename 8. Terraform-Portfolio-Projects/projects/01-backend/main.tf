variable "trusted_principal_arns" {
  type        = set(string)
  description = "Specific existing human/workload role ARNs permitted to assume environment state roles."
  validation {
    condition     = length(var.trusted_principal_arns) > 0 && alltrue([for arn in var.trusted_principal_arns : can(regex("^arn:aws:iam::[0-9]{12}:role/.+", arn))])
    error_message = "Supply explicit IAM role ARNs; do not trust an entire account."
  }
}
resource "aws_kms_key" "state" {
  description             = "Veriqta Terraform state encryption"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  lifecycle { prevent_destroy = true }
}
resource "aws_s3_bucket" "state" {
  bucket = "${var.name}-${var.account_id}-${var.region}-state"
  lifecycle { prevent_destroy = true }
}
resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id
  versioning_configuration { status = "Enabled" }
}
resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.state.arn
    }
    bucket_key_enabled = true
  }
}
resource "aws_s3_bucket_public_access_block" "state" {
  bucket                  = aws_s3_bucket.state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
resource "aws_s3_bucket_policy" "state" {
  bucket = aws_s3_bucket.state.id
  policy = jsonencode({ Version = "2012-10-17", Statement = [
    { Sid = "SecureTransport", Effect = "Deny", Principal = "*", Action = "s3:*", Resource = [aws_s3_bucket.state.arn, "${aws_s3_bucket.state.arn}/*"], Condition = { Bool = { "aws:SecureTransport" = "false" }
    } },
    { Sid = "DoNotDeleteLiveState", Effect = "Deny", Principal = "*", Action = ["s3:DeleteObject", "s3:DeleteObjectVersion"], Resource = "${aws_s3_bucket.state.arn}/environments/*/terraform.tfstate" }
  ] })
}
resource "aws_s3_bucket_lifecycle_configuration" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    id     = "abort-incomplete-uploads"
    status = "Enabled"
    filter { prefix = "" }
    abort_incomplete_multipart_upload { days_after_initiation = 7 }
  }
}
resource "aws_iam_role" "environment" {
  for_each = toset(["dev", "staging", "prod"])
  name     = "${var.name}-${each.key}-state"
  assume_role_policy = jsonencode({ Version = "2012-10-17", Statement = [{ Effect = "Allow", Action = "sts:AssumeRole", Principal = { AWS = sort(tolist(var.trusted_principal_arns)) }
  }] })
}
resource "aws_iam_role_policy" "state" {
  for_each = aws_iam_role.environment
  role     = each.value.id
  policy = jsonencode({ Version = "2012-10-17", Statement = [
    { Effect = "Allow", Action = "s3:ListBucket", Resource = aws_s3_bucket.state.arn, Condition = { StringLike = { "s3:prefix" = ["environments/${each.key}/*"] }
    } },
    { Effect = "Allow", Action = ["s3:GetObject", "s3:PutObject"], Resource = ["${aws_s3_bucket.state.arn}/environments/${each.key}/terraform.tfstate", "${aws_s3_bucket.state.arn}/environments/${each.key}/*/terraform.tfstate"] },
    { Effect = "Allow", Action = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"], Resource = ["${aws_s3_bucket.state.arn}/environments/${each.key}/terraform.tfstate.tflock", "${aws_s3_bucket.state.arn}/environments/${each.key}/*/terraform.tfstate.tflock"] },
    { Effect = "Allow", Action = ["kms:Encrypt", "kms:Decrypt", "kms:GenerateDataKey"], Resource = aws_kms_key.state.arn, Condition = { StringEquals = { "kms:ViaService" = "s3.${var.region}.amazonaws.com" }
    } }
  ] })
}
resource "aws_s3_bucket" "archive" {
  bucket              = "${var.name}-${var.account_id}-${var.region}-archive"
  object_lock_enabled = true
  lifecycle { prevent_destroy = true }
}
resource "aws_s3_bucket_versioning" "archive" {
  bucket = aws_s3_bucket.archive.id
  versioning_configuration { status = "Enabled" }
}
resource "aws_s3_bucket_public_access_block" "archive" {
  bucket                  = aws_s3_bucket.archive.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
resource "aws_s3_bucket_server_side_encryption_configuration" "archive" {
  bucket = aws_s3_bucket.archive.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.state.arn
    }
  }
}
resource "aws_s3_bucket_object_lock_configuration" "archive" {
  bucket     = aws_s3_bucket.archive.id
  depends_on = [aws_s3_bucket_versioning.archive]
  rule {
    default_retention {
      mode = "GOVERNANCE"
      days = 7
    }
  }
}
output "bucket" { value = aws_s3_bucket.state.id }
output "kms_key_arn" { value = aws_kms_key.state.arn }
output "archive_bucket" { value = aws_s3_bucket.archive.id }
output "state_role_arns" {
  value = { for k, v in aws_iam_role.environment : k => v.arn }
}
