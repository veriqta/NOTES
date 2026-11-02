terraform {
  required_version = ">= 1.10, < 2.0"
  required_providers {
    aws = { source = "hashicorp/aws", version = "6.19.0" }
  }
}
provider "aws" {
  region              = var.region
  allowed_account_ids = [var.account_id]
  default_tags { tags = local.tags }
}
variable "region" {
  type    = string
  default = "us-east-1"
}
variable "account_id" {
  type = string
  validation {
    condition     = can(regex("^[0-9]{12}$", var.account_id))
    error_message = "Supply the expected twelve-digit AWS account ID."
  }
}
variable "name" {
  type    = string
  default = "veriqta-lab"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,22}$", var.name))
    error_message = "Use 3..23 lowercase letters, digits or hyphens, beginning with a letter."
  }
}
variable "environment" {
  type    = string
  default = "dev"
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Choose dev, staging or prod."
  }
}
locals {
  tags = {
    Project     = var.name
    Environment = var.environment
    Owner       = "veriqta"
    CostCenter  = "training"
    ManagedBy   = "terraform"
    Application = "portfolio"
  }
}

provider "aws" {
  alias               = "dr"
  region              = var.recovery_region
  allowed_account_ids = [var.account_id]
  default_tags { tags = local.tags }
}
variable "recovery_region" {
  type    = string
  default = "us-west-2"
  validation {
    condition     = var.recovery_region != var.region
    error_message = "Primary and recovery Regions must differ."
  }
}
