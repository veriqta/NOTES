variable "cidr" { type = string }
variable "deletion_protection" {
  type    = bool
  default = true
}
variable "database_engine_version" { type = string }
variable "snapshot_identifier" {
  type    = string
  default = null
}
variable "final_snapshot_suffix" {
  type    = string
  default = "retained"
}
module "network" {
  source             = "../modules/network"
  name               = var.name
  cidr               = var.cidr
  az_count           = 3
  enable_nat         = true
  allow_database     = true
  interface_services = ["ssm", "ssmmessages", "secretsmanager", "logs", "ecr.api", "ecr.dkr", "sts", "ec2", "monitoring"]
}
resource "aws_kms_key" "data" {
  enable_key_rotation     = true
  deletion_window_in_days = 30
  lifecycle { prevent_destroy = true }
}
module "database" {
  source                     = "../modules/database"
  name                       = var.name
  vpc_id                     = module.network.vpc_id
  subnet_ids                 = module.network.database_subnet_ids
  workload_security_group_id = module.network.workload_security_group_id
  kms_key_arn                = aws_kms_key.data.arn
  engine_version             = var.database_engine_version
  deletion_protection        = var.deletion_protection
  snapshot_identifier        = var.snapshot_identifier
  final_snapshot_suffix      = var.final_snapshot_suffix
}
resource "aws_sqs_queue" "dead" {
  name                      = "${var.name}-dead"
  sqs_managed_sse_enabled   = true
  message_retention_seconds = 1209600
}
resource "aws_sqs_queue" "jobs" {
  name                       = "${var.name}-jobs"
  sqs_managed_sse_enabled    = true
  visibility_timeout_seconds = 60
  redrive_policy             = jsonencode({ deadLetterTargetArn = aws_sqs_queue.dead.arn, maxReceiveCount = 5 })
}
resource "aws_s3_bucket" "objects" { bucket = "${var.name}-${var.account_id}-${var.region}-objects" }
resource "aws_s3_bucket_versioning" "objects" {
  bucket = aws_s3_bucket.objects.id
  versioning_configuration { status = "Enabled" }
}
resource "aws_s3_bucket_public_access_block" "objects" {
  bucket                  = aws_s3_bucket.objects.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
resource "aws_s3_bucket_server_side_encryption_configuration" "objects" {
  bucket = aws_s3_bucket.objects.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.data.arn
    }
  }
}
resource "aws_s3_bucket_policy" "objects" {
  bucket = aws_s3_bucket.objects.id
  policy = jsonencode({ Version = "2012-10-17", Statement = [{ Effect = "Deny", Principal = "*", Action = "s3:*", Resource = [aws_s3_bucket.objects.arn, "${aws_s3_bucket.objects.arn}/*"], Condition = { Bool = { "aws:SecureTransport" = "false" } } }] })
}
resource "aws_ecr_repository" "application" {
  name                 = var.name
  image_tag_mutability = "IMMUTABLE"
  image_scanning_configuration { scan_on_push = true }
  force_delete = false
}
resource "aws_backup_vault" "this" {
  name        = var.name
  kms_key_arn = aws_kms_key.data.arn
}
output "contract" { value = { vpc_id = module.network.vpc_id, private_subnet_ids = module.network.private_subnet_ids, public_subnet_ids = module.network.public_subnet_ids, workload_sg_id = module.network.workload_security_group_id, secret_arn = module.database.secret_arn, db_host = module.database.endpoint, db_arn = module.database.arn, kms_key_arn = aws_kms_key.data.arn, queue_arn = aws_sqs_queue.jobs.arn, queue_url = aws_sqs_queue.jobs.url, bucket = aws_s3_bucket.objects.id, repository_url = aws_ecr_repository.application.repository_url, vault_arn = aws_backup_vault.this.arn, vault_name = aws_backup_vault.this.name } }
