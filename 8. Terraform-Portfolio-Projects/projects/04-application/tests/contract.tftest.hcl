mock_provider "aws" {
  source = "./tests"
}
variables {
  account_id         = "123456789012"
  application_ami_id = "ami-0123456789abcdef0"
  client_cidrs       = ["192.0.2.0/24"]
}
run "contract" {
  command = plan
  assert {
    condition     = module.database.identifier == "veriqta-lab-db"
    error_message = "The database identifier contract changed."
  }
}
