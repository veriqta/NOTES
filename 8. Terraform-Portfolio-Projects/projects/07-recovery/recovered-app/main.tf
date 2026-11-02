terraform {
  required_version = ">= 1.10, < 2.0"
  required_providers { aws = { source = "hashicorp/aws", version = "6.19.0" } }
}
variable "account_id" { type = string }
variable "region" { type = string }
variable "name" { type = string }
variable "ami_id" { type = string }
variable "client_cidrs" { type = list(string) }
variable "certificate_arn" { type = string }
variable "database_endpoint" { type = string }
variable "database_identifier" { type = string }
variable "secret_arn" { type = string }
variable "kms_key_arn" { type = string }
variable "network" {
  type = object({ vpc_id = string, private_subnet_ids = list(string), public_subnet_ids = list(string), workload_security_group_id = string })
}
provider "aws" {
  region              = var.region
  allowed_account_ids = [var.account_id]
  default_tags { tags = { Project = var.name, Owner = "veriqta", Environment = "recovery", ManagedBy = "Terraform" } }
}
module "compute" {
  source                     = "../../../modules/compute"
  name                       = var.name
  region                     = var.region
  vpc_id                     = var.network.vpc_id
  private_subnet_ids         = var.network.private_subnet_ids
  public_subnet_ids          = var.network.public_subnet_ids
  workload_security_group_id = var.network.workload_security_group_id
  ami_id                     = var.ami_id
  ingress_cidrs              = var.client_cidrs
  certificate_arn            = var.certificate_arn
  db_host                    = var.database_endpoint
  secret_arn                 = var.secret_arn
  kms_key_arn                = var.kms_key_arn
}
module "monitoring" {
  source              = "../../../modules/monitoring"
  name                = var.name
  alb_suffix          = module.compute.alb_arn_suffix
  target_group_suffix = module.compute.target_group_suffix
  database_identifier = var.database_identifier
  asg_name            = module.compute.asg_name
}
output "alb_dns" { value = module.compute.alb_dns }
output "alb_zone_id" { value = module.compute.alb_zone_id }
