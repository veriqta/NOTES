mock_provider "aws" {
  source = "./tests"
}
variables {
  account_id = "123456789012"

}
run "contract" {
  command = plan
  assert {
    condition     = aws_instance.probe.associate_public_ip_address == false
    error_message = "The probe must stay private."
  }
}
