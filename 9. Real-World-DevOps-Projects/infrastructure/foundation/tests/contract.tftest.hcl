mock_provider "aws" {
  source = "./tests"
}
variables {
  account_id              = "123456789012"
  region                  = "us-east-1"
  name                    = "veriqta-test"
  cidr                    = "10.90.0.0/16"
  database_engine_version = "17.6"
}
run "contract" {
  command = plan
  assert {
    condition     = aws_sqs_queue.jobs.sqs_managed_sse_enabled && aws_s3_bucket_public_access_block.objects.restrict_public_buckets
    error_message = "Queues must be encrypted and object storage private."
  }
}
