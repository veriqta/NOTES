variable "final_snapshot_suffix" {
  type    = string
  default = "retained"
}
variable "database_engine_version" {
  type    = string
  default = null
}
variable "application_ami_id" { type = string }
variable "client_cidrs" { type = list(string) }
variable "certificate_arn" {
  type    = string
  default = null
}
variable "deletion_protection" {
  type    = bool
  default = true
}
variable "desired_capacity" {
  type    = number
  default = 6
}
module "network" {
  source             = "../../modules/network"
  name               = var.name
  az_count           = 3
  allow_database     = true
  interface_services = ["ssm", "ssmmessages", "logs", "secretsmanager", "monitoring", "ec2"]
}
resource "aws_kms_key" "data" {
  lifecycle { prevent_destroy = true }
  description             = "Veriqta database and managed-secret key"
  enable_key_rotation     = true
  deletion_window_in_days = 30
}
module "database" {
  source                     = "../../modules/database"
  name                       = var.name
  vpc_id                     = module.network.vpc_id
  subnet_ids                 = module.network.database_subnet_ids
  workload_security_group_id = module.network.workload_security_group_id
  kms_key_arn                = aws_kms_key.data.arn
  deletion_protection        = var.deletion_protection
  engine_version             = var.database_engine_version
  final_snapshot_suffix      = var.final_snapshot_suffix
}
module "compute" {
  source                     = "../../modules/compute"
  name                       = var.name
  region                     = var.region
  vpc_id                     = module.network.vpc_id
  private_subnet_ids         = module.network.private_subnet_ids
  public_subnet_ids          = module.network.public_subnet_ids
  workload_security_group_id = module.network.workload_security_group_id
  ami_id                     = var.application_ami_id
  db_host                    = module.database.endpoint
  secret_arn                 = module.database.secret_arn
  kms_key_arn                = aws_kms_key.data.arn
  desired_capacity           = var.desired_capacity
  ingress_cidrs              = var.client_cidrs
  certificate_arn            = var.certificate_arn
}
module "monitoring" {
  source              = "../../modules/monitoring"
  name                = var.name
  alb_suffix          = module.compute.alb_arn_suffix
  target_group_suffix = module.compute.target_group_suffix
  database_identifier = module.database.identifier
  asg_name            = module.compute.asg_name
}
output "alb_dns" { value = module.compute.alb_dns }
output "asg_name" { value = module.compute.asg_name }
output "target_group_arn" { value = module.compute.target_group_arn }
output "database_arn" { value = module.database.arn }
output "database_identifier" { value = module.database.identifier }
output "kms_key_arn" { value = aws_kms_key.data.arn }
output "alarm_topic_arn" { value = module.monitoring.alarm_topic_arn }
