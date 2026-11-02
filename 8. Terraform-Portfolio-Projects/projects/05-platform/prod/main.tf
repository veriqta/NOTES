variable "account_id" { type = string }
terraform {
  required_version = ">= 1.10, < 2.0"
  required_providers {
    aws = { source = "hashicorp/aws", version = "6.19.0" }
  }
}

provider "aws" {
  region              = "us-east-1"
  allowed_account_ids = [var.account_id]
}
module "network" {
  source             = "../../../modules/network"
  name               = "veriqta-prod"
  az_count           = 3
  interface_services = []
}
output "network" {
  value = { vpc_id = module.network.vpc_id, private_subnet_ids = module.network.private_subnet_ids }
}
