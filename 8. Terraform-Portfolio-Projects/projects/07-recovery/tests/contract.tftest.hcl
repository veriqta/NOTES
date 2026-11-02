mock_provider "aws" {
  source = "./tests"
}
mock_provider "aws" {
  alias  = "dr"
  source = "./tests"
}
variables {
  account_id           = "123456789012"
  database_arn         = "arn:aws:rds:us-east-1:123456789012:db:veriqta"
  database_kms_key_arn = "arn:aws:kms:us-east-1:123456789012:key/00000000-0000-0000-0000-000000000000"
  primary_alb_dns      = "veriqta.example.invalid"
  primary_alb_zone_id  = "Z35SXDOTRQ7X7K"
}
run "contract" {
  command = plan
  assert {
    condition     = length(aws_route53_record.primary) == 0
    error_message = "DNS failover must stay opt-in until data recovery is verified."
  }
}
