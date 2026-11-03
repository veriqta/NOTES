mock_data "aws_caller_identity" {
  defaults = { account_id = "123456789012", arn = "arn:aws:iam::123456789012:root", user_id = "mock" }
}
mock_data "aws_region" { defaults = { name = "us-east-1", region = "us-east-1" } }
mock_data "aws_availability_zones" {
  defaults = { names = ["us-east-1a", "us-east-1b", "us-east-1c"], zone_ids = ["use1-az1", "use1-az2", "use1-az3"] }
}
mock_data "aws_ssm_parameter" { defaults = { value = "ami-0123456789abcdef0" } }
mock_resource "aws_kms_key" {
  defaults = { arn = "arn:aws:kms:us-east-1:123456789012:key/00000000-0000-0000-0000-000000000000", key_id = "00000000-0000-0000-0000-000000000000" }
}
mock_resource "aws_iam_role" { defaults = { arn = "arn:aws:iam::123456789012:role/veriqta-mock" } }
mock_resource "aws_iam_instance_profile" { defaults = { arn = "arn:aws:iam::123456789012:instance-profile/veriqta-mock" } }
mock_resource "aws_s3_bucket" { defaults = { arn = "arn:aws:s3:::veriqta-mock-bucket" } }
mock_resource "aws_db_instance" {
  defaults = { arn = "arn:aws:rds:us-east-1:123456789012:db:veriqta-mock", address = "veriqta.example.invalid", master_user_secret = [{ secret_arn = "arn:aws:secretsmanager:us-east-1:123456789012:secret:veriqta-AbCdEf", secret_status = "active", kms_key_id = "arn:aws:kms:us-east-1:123456789012:key/00000000-0000-0000-0000-000000000000" }] }
}
mock_resource "aws_lb" {
  defaults = { arn = "arn:aws:elasticloadbalancing:us-east-1:123456789012:loadbalancer/app/veriqta/0000000000000000", arn_suffix = "app/veriqta/0000000000000000", dns_name = "veriqta.example.invalid", zone_id = "Z35SXDOTRQ7X7K" }
}
mock_resource "aws_lb_target_group" {
  defaults = { arn = "arn:aws:elasticloadbalancing:us-east-1:123456789012:targetgroup/veriqta/0000000000000000", arn_suffix = "targetgroup/veriqta/0000000000000000" }
}
mock_resource "aws_cloudwatch_log_group" { defaults = { arn = "arn:aws:logs:us-east-1:123456789012:log-group:veriqta" } }
mock_resource "aws_sns_topic" { defaults = { arn = "arn:aws:sns:us-east-1:123456789012:veriqta" } }
mock_resource "aws_backup_vault" { defaults = { arn = "arn:aws:backup:us-west-2:123456789012:backup-vault:veriqta" } }

mock_resource "aws_sqs_queue" {
  defaults = { arn = "arn:aws:sqs:us-east-1:123456789012:veriqta-jobs", url = "https://sqs.us-east-1.amazonaws.com/123456789012/veriqta-jobs" }
}
mock_resource "aws_eks_cluster" {
  defaults = { arn = "arn:aws:eks:us-east-1:123456789012:cluster/veriqta", endpoint = "https://example.invalid" }
}
