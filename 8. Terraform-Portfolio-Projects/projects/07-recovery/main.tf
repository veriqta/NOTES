variable "database_arn" { type = string }
variable "primary_alb_dns" { type = string }
variable "primary_alb_zone_id" { type = string }
variable "recovery_alb_dns" {
  type    = string
  default = null
}
variable "recovery_alb_zone_id" {
  type    = string
  default = null
}
variable "route53_zone_id" {
  type    = string
  default = null
}
variable "dns_name" {
  type    = string
  default = null
}
variable "recovery_data_verified" {
  type    = bool
  default = false
}
resource "aws_kms_key" "primary" {
  lifecycle { prevent_destroy = true }
  enable_key_rotation     = true
  deletion_window_in_days = 30
}
resource "aws_kms_key" "dr" {
  lifecycle { prevent_destroy = true }
  provider                = aws.dr
  enable_key_rotation     = true
  deletion_window_in_days = 30
}
resource "aws_s3_bucket" "primary" { bucket = "${var.name}-${var.account_id}-${var.region}-data" }
resource "aws_s3_bucket" "dr" {
  provider = aws.dr
  bucket   = "${var.name}-${var.account_id}-${var.recovery_region}-data"
}
resource "aws_s3_bucket_versioning" "primary" {
  bucket = aws_s3_bucket.primary.id
  versioning_configuration { status = "Enabled" }
}
resource "aws_s3_bucket_versioning" "dr" {
  provider = aws.dr
  bucket   = aws_s3_bucket.dr.id
  versioning_configuration { status = "Enabled" }
}
resource "aws_s3_bucket_public_access_block" "primary" {
  bucket                  = aws_s3_bucket.primary.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
resource "aws_s3_bucket_public_access_block" "dr" {
  provider                = aws.dr
  bucket                  = aws_s3_bucket.dr.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
resource "aws_s3_bucket_server_side_encryption_configuration" "primary" {
  bucket = aws_s3_bucket.primary.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.primary.arn
    }
  }
}
resource "aws_s3_bucket_server_side_encryption_configuration" "dr" {
  provider = aws.dr
  bucket   = aws_s3_bucket.dr.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.dr.arn
    }
  }
}
resource "aws_iam_role" "replication" {
  name               = "${var.name}-replication"
  assume_role_policy = jsonencode({ Version = "2012-10-17", Statement = [{ Effect = "Allow", Action = "sts:AssumeRole", Principal = { Service = "s3.amazonaws.com" } }] })
}
resource "aws_iam_role_policy" "replication" {
  role = aws_iam_role.replication.id
  policy = jsonencode({ Version = "2012-10-17", Statement = [
    { Effect = "Allow", Action = ["s3:GetReplicationConfiguration", "s3:ListBucket"], Resource = aws_s3_bucket.primary.arn },
    { Effect = "Allow", Action = ["s3:GetObjectVersionForReplication", "s3:GetObjectVersionAcl", "s3:GetObjectVersionTagging"], Resource = "${aws_s3_bucket.primary.arn}/*" },
    { Effect = "Allow", Action = ["s3:ReplicateObject", "s3:ReplicateTags", "s3:ReplicateDelete"], Resource = "${aws_s3_bucket.dr.arn}/*" },
    { Effect = "Allow", Action = "kms:Decrypt", Resource = aws_kms_key.primary.arn, Condition = { StringEquals = { "kms:ViaService" = "s3.${var.region}.amazonaws.com" } } },
    { Effect = "Allow", Action = ["kms:Encrypt", "kms:GenerateDataKey"], Resource = aws_kms_key.dr.arn, Condition = { StringEquals = { "kms:ViaService" = "s3.${var.recovery_region}.amazonaws.com" } } }
  ] })
}
resource "aws_s3_bucket_replication_configuration" "this" {
  bucket     = aws_s3_bucket.primary.id
  role       = aws_iam_role.replication.arn
  depends_on = [aws_s3_bucket_versioning.primary, aws_s3_bucket_versioning.dr, aws_iam_role_policy.replication]
  rule {
    id     = "all-new-objects"
    status = "Enabled"
    filter { prefix = "" }
    delete_marker_replication { status = "Disabled" }
    source_selection_criteria {
      sse_kms_encrypted_objects { status = "Enabled" }
    }
    destination {
      bucket = aws_s3_bucket.dr.arn
      encryption_configuration { replica_kms_key_id = aws_kms_key.dr.arn }
    }
  }
}
resource "aws_backup_vault" "primary" {
  name        = "${var.name}-primary"
  kms_key_arn = aws_kms_key.primary.arn
}
resource "aws_backup_vault" "dr" {
  provider    = aws.dr
  name        = "${var.name}-recovery"
  kms_key_arn = aws_kms_key.dr.arn
}
resource "aws_iam_role" "backup" {
  name               = "${var.name}-backup"
  assume_role_policy = jsonencode({ Version = "2012-10-17", Statement = [{ Effect = "Allow", Action = "sts:AssumeRole", Principal = { Service = "backup.amazonaws.com" } }] })
}
resource "aws_iam_role_policy_attachment" "backup" {
  role       = aws_iam_role.backup.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup"
}
resource "aws_iam_role_policy" "backup_keys" {
  role   = aws_iam_role.backup.id
  policy = jsonencode({ Version = "2012-10-17", Statement = [{ Effect = "Allow", Action = ["kms:Decrypt", "kms:Encrypt", "kms:GenerateDataKey", "kms:DescribeKey", "kms:CreateGrant"], Resource = [aws_kms_key.primary.arn, aws_kms_key.dr.arn, var.database_kms_key_arn] }] })
}
variable "database_kms_key_arn" { type = string }
resource "aws_backup_plan" "this" {
  name = var.name
  rule {
    rule_name         = "daily-regional-copy"
    target_vault_name = aws_backup_vault.primary.name
    schedule          = "cron(0 3 * * ? *)"
    lifecycle { delete_after = 14 }
    copy_action {
      destination_vault_arn = aws_backup_vault.dr.arn
      lifecycle { delete_after = 30 }
    }
  }
}
resource "aws_backup_selection" "database" {
  name         = "${var.name}-database"
  plan_id      = aws_backup_plan.this.id
  iam_role_arn = aws_iam_role.backup.arn
  resources    = [var.database_arn]
  depends_on   = [aws_iam_role_policy_attachment.backup, aws_iam_role_policy.backup_keys]
}
resource "aws_iam_role" "restore" {
  name               = "${var.name}-restore"
  assume_role_policy = jsonencode({ Version = "2012-10-17", Statement = [{ Effect = "Allow", Action = "sts:AssumeRole", Principal = { Service = "backup.amazonaws.com" } }] })
}
resource "aws_iam_role_policy_attachment" "restore" {
  role       = aws_iam_role.restore.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForRestores"
}
resource "aws_iam_role_policy" "restore_key" {
  role   = aws_iam_role.restore.id
  policy = jsonencode({ Version = "2012-10-17", Statement = [{ Effect = "Allow", Action = ["kms:Decrypt", "kms:DescribeKey", "kms:GenerateDataKey", "kms:CreateGrant"], Resource = aws_kms_key.dr.arn }] })
}
module "recovery_network" {
  source             = "../../modules/network"
  providers          = { aws = aws.dr }
  name               = "${var.name}-dr"
  cidr               = "10.72.0.0/16"
  allow_database     = true
  interface_services = ["ssm", "ssmmessages", "logs", "secretsmanager", "monitoring", "ec2"]
}
resource "aws_db_subnet_group" "restore" {
  provider   = aws.dr
  name       = "${var.name}-restore"
  subnet_ids = module.recovery_network.database_subnet_ids
}
resource "aws_security_group" "restore" {
  provider    = aws.dr
  name_prefix = "${var.name}-restore-db-"
  vpc_id      = module.recovery_network.vpc_id
  ingress {
    protocol        = "tcp"
    from_port       = 5432
    to_port         = 5432
    security_groups = [module.recovery_network.workload_security_group_id]
  }
  egress = []
}
resource "aws_route53_record" "primary" {
  count          = var.route53_zone_id == null ? 0 : 1
  zone_id        = var.route53_zone_id
  name           = var.dns_name
  type           = "A"
  set_identifier = "primary"
  failover_routing_policy { type = "PRIMARY" }
  alias {
    name                   = var.primary_alb_dns
    zone_id                = var.primary_alb_zone_id
    evaluate_target_health = true
  }
}
resource "aws_route53_record" "recovery" {
  count          = var.route53_zone_id == null ? 0 : 1
  zone_id        = var.route53_zone_id
  name           = var.dns_name
  type           = "A"
  set_identifier = "recovery"
  failover_routing_policy { type = "SECONDARY" }
  alias {
    name                   = var.recovery_alb_dns
    zone_id                = var.recovery_alb_zone_id
    evaluate_target_health = true
  }
  lifecycle {
    precondition {
      condition     = var.recovery_data_verified && var.recovery_alb_dns != null && var.recovery_alb_zone_id != null
      error_message = "Do not publish the failover pair until recovery data and the recovery application are verified."
    }
  }
}
output "primary_bucket" { value = aws_s3_bucket.primary.id }
output "recovery_bucket" { value = aws_s3_bucket.dr.id }
output "recovery_vault_name" { value = aws_backup_vault.dr.name }
output "restore_role_arn" { value = aws_iam_role.restore.arn }
output "recovery_kms_key_arn" { value = aws_kms_key.dr.arn }
output "restore_subnet_group" { value = aws_db_subnet_group.restore.name }
output "restore_security_group" { value = aws_security_group.restore.id }
output "recovery_network" {
  value = { vpc_id = module.recovery_network.vpc_id, private_subnet_ids = module.recovery_network.private_subnet_ids, public_subnet_ids = module.recovery_network.public_subnet_ids, workload_security_group_id = module.recovery_network.workload_security_group_id }
}

output "primary_vault_name" { value = aws_backup_vault.primary.name }
output "recovery_vault_arn" { value = aws_backup_vault.dr.arn }
output "backup_role_arn" { value = aws_iam_role.backup.arn }
