mock_provider "aws" {
  source = "./tests"
}
variables {
  account_id             = "123456789012"
  trusted_principal_arns = ["arn:aws:iam::123456789012:role/VeriqtaOperator"]
}
run "contract" {
  command = plan
  assert {
    condition     = aws_s3_bucket_versioning.state.versioning_configuration[0].status == "Enabled"
    error_message = "State must remain versioned."
  }
  assert {
    condition     = length(aws_iam_role.environment) == 3
    error_message = "Each environment needs a state role."
  }
}
