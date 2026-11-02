variable "enable_nat" {
  type    = bool
  default = false
}
variable "enable_proxy" {
  type    = bool
  default = true
}
variable "interface_services" {
  type    = set(string)
  default = ["ssm", "ssmmessages", "logs", "secretsmanager"]
}
module "network" {
  interface_services = var.interface_services
  source             = "../../modules/network"
  name               = var.name
  enable_nat         = var.enable_nat
  enable_proxy       = var.enable_proxy
}
output "vpc_id" { value = module.network.vpc_id }
output "proxy_ip" { value = module.network.proxy_private_ip }
output "private_subnet_ids" { value = module.network.private_subnet_ids }
output "workload_sg_id" { value = module.network.workload_security_group_id }

data "aws_ssm_parameter" "ami" { name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64" }
resource "aws_iam_role" "probe" {
  name               = "${var.name}-probe"
  assume_role_policy = jsonencode({ Version = "2012-10-17", Statement = [{ Effect = "Allow", Action = "sts:AssumeRole", Principal = { Service = "ec2.amazonaws.com" } }] })
}
resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.probe.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}
resource "aws_iam_instance_profile" "probe" { role = aws_iam_role.probe.name }
resource "aws_instance" "probe" {
  ami                         = nonsensitive(data.aws_ssm_parameter.ami.value)
  instance_type               = "t3.micro"
  subnet_id                   = module.network.private_subnet_ids[0]
  vpc_security_group_ids      = [module.network.workload_security_group_id]
  iam_instance_profile        = aws_iam_instance_profile.probe.name
  associate_public_ip_address = false
  metadata_options { http_tokens = "required" }
  root_block_device { encrypted = true }
  tags = { Name = "${var.name}-probe" }
}
output "probe_instance_id" { value = aws_instance.probe.id }
