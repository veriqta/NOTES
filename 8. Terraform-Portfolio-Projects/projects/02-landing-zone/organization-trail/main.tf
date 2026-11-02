variable "state_bucket_arn" { type = string }
variable "archive_bucket_name" { type = string }
resource "aws_cloudtrail" "organization" {
  event_selector {
    read_write_type           = "All"
    include_management_events = true
    data_resource {
      type   = "AWS::S3::Object"
      values = ["${var.state_bucket_arn}/"]
    }
  }

  name                          = "${var.name}-organization"
  s3_bucket_name                = var.archive_bucket_name
  is_organization_trail         = true
  is_multi_region_trail         = true
  include_global_service_events = true
  enable_log_file_validation    = true
}
output "trail_arn" { value = aws_cloudtrail.organization.arn }
