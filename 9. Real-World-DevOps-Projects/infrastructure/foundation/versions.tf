terraform {
  required_version = ">= 1.10, < 2.0"
  required_providers { aws = { source = "hashicorp/aws", version = "6.19.0" } }
}
provider "aws" {
  region              = var.region
  allowed_account_ids = [var.account_id]
  default_tags { tags = { Owner = "veriqta", Project = var.name, Environment = "lab", ManagedBy = "Terraform" } }
}
variable "account_id" { type = string }
variable "region" { type = string }
variable "name" { type = string }
