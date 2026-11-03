variable "name" { type = string }
variable "cidr" {
  type    = string
  default = "10.64.0.0/16"
  validation {
    condition     = can(cidrsubnet(var.cidr, 8, 30))
    error_message = "Supply an IPv4 network large enough for the subnet layout."
  }
}
variable "az_count" {
  type    = number
  default = 2
  validation {
    condition     = contains([2, 3], var.az_count)
    error_message = "Choose two or three AZs."
  }
}
variable "interface_services" {
  type    = set(string)
  default = ["ssm", "ssmmessages", "logs", "secretsmanager"]
}
variable "enable_nat" {
  type    = bool
  default = false
}
variable "enable_proxy" {
  type    = bool
  default = false
}
variable "proxy_domains" {
  type    = list(string)
  default = [".amazonlinux.com", "example.com"]
  validation {
    condition     = length(var.proxy_domains) > 0 && alltrue([for d in var.proxy_domains : can(regex("^[.]?[a-zA-Z0-9][a-zA-Z0-9.-]*[a-zA-Z0-9]$", d))])
    error_message = "Use explicit domain names without whitespace or proxy directives."
  }

}
variable "allow_database" {
  type    = bool
  default = false
}
variable "flow_logs" {
  type    = bool
  default = true
}
data "aws_availability_zones" "available" { state = "available" }
data "aws_region" "current" {}
data "aws_caller_identity" "current" {}
locals {
  azs            = slice(data.aws_availability_zones.available.names, 0, var.az_count)
  az_map         = { for i, az in local.azs : az => i }
  private_cidrs  = [for i in range(var.az_count) : cidrsubnet(var.cidr, 8, i + 10)]
  database_cidrs = [for i in range(var.az_count) : cidrsubnet(var.cidr, 8, i + 20)]
}
resource "aws_vpc" "this" {
  cidr_block           = var.cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = { Name = var.name }
}
resource "aws_internet_gateway" "this" { vpc_id = aws_vpc.this.id }
resource "aws_subnet" "public" {
  for_each                = local.az_map
  vpc_id                  = aws_vpc.this.id
  availability_zone       = each.key
  cidr_block              = cidrsubnet(var.cidr, 8, each.value)
  map_public_ip_on_launch = false
  tags                    = { Name = "${var.name}-public-${each.key}" }
}
resource "aws_subnet" "private" {
  for_each          = local.az_map
  vpc_id            = aws_vpc.this.id
  availability_zone = each.key
  cidr_block        = cidrsubnet(var.cidr, 8, each.value + 10)
  tags              = { Name = "${var.name}-private-${each.key}" }
}
resource "aws_subnet" "database" {
  for_each          = local.az_map
  vpc_id            = aws_vpc.this.id
  availability_zone = each.key
  cidr_block        = cidrsubnet(var.cidr, 8, each.value + 20)
}
resource "aws_route_table" "public" { vpc_id = aws_vpc.this.id }
resource "aws_route" "internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}
resource "aws_route_table_association" "public" {
  for_each       = aws_subnet.public
  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}
resource "aws_route_table" "private" {
  for_each = local.az_map
  vpc_id   = aws_vpc.this.id
}
resource "aws_route_table_association" "private" {
  for_each       = aws_subnet.private
  subnet_id      = each.value.id
  route_table_id = aws_route_table.private[each.key].id
}
resource "aws_route_table" "database" { vpc_id = aws_vpc.this.id }
resource "aws_route_table_association" "database" {
  for_each       = aws_subnet.database
  subnet_id      = each.value.id
  route_table_id = aws_route_table.database.id
}
resource "aws_eip" "nat" {
  for_each = var.enable_nat ? local.az_map : {}
  domain   = "vpc"
}
resource "aws_nat_gateway" "this" {
  for_each      = aws_eip.nat
  allocation_id = each.value.id
  subnet_id     = aws_subnet.public[each.key].id
  depends_on    = [aws_route.internet]
}
resource "aws_route" "nat" {
  for_each               = aws_nat_gateway.this
  route_table_id         = aws_route_table.private[each.key].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = each.value.id
}
resource "aws_security_group" "endpoints" {
  name_prefix = "${var.name}-endpoints-"
  vpc_id      = aws_vpc.this.id
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = local.private_cidrs
  }
  egress = []
}
resource "aws_vpc_endpoint" "gateway" {
  for_each          = toset(["s3", "dynamodb"])
  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${data.aws_region.current.region}.${each.key}"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [for rt in aws_route_table.private : rt.id]
  policy = jsonencode({ Version = "2012-10-17", Statement = [{ Effect = "Allow", Principal = "*", Action = "*", Resource = "*", Condition = { StringEquals = { "aws:PrincipalAccount" = data.aws_caller_identity.current.account_id }
  } }] })
}
resource "aws_vpc_endpoint" "interface" {
  for_each            = var.interface_services
  vpc_id              = aws_vpc.this.id
  service_name        = "com.amazonaws.${data.aws_region.current.region}.${each.key}"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids          = [for s in aws_subnet.private : s.id]
  security_group_ids  = [aws_security_group.endpoints.id]
  policy = jsonencode({ Version = "2012-10-17", Statement = [{ Effect = "Allow", Principal = "*", Action = "*", Resource = "*", Condition = { StringEquals = { "aws:PrincipalAccount" = data.aws_caller_identity.current.account_id }
  } }] })
}
resource "aws_security_group" "workload" {
  name_prefix = "${var.name}-workload-"
  vpc_id      = aws_vpc.this.id
  ingress     = []
  egress {
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.endpoints.id]
  }
  egress {
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    prefix_list_ids = [for ep in aws_vpc_endpoint.gateway : ep.prefix_list_id]
  }
  dynamic "egress" {
    for_each = var.allow_database ? [1] : []
    content {
      from_port   = 5432
      to_port     = 5432
      protocol    = "tcp"
      cidr_blocks = local.database_cidrs
    }
  }
  dynamic "egress" {
    for_each = var.enable_proxy ? [1] : []
    content {
      from_port       = 3128
      to_port         = 3128
      protocol        = "tcp"
      security_groups = [aws_security_group.proxy[0].id]
    }
  }
}
resource "aws_security_group" "proxy" {
  count       = var.enable_proxy ? 1 : 0
  name_prefix = "${var.name}-proxy-"
  vpc_id      = aws_vpc.this.id
  ingress {
    from_port   = 3128
    to_port     = 3128
    protocol    = "tcp"
    cidr_blocks = local.private_cidrs
  }
  egress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
data "aws_ssm_parameter" "ami" {
  count = var.enable_proxy ? 1 : 0
  name  = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}
resource "aws_instance" "proxy" {
  count                       = var.enable_proxy ? 1 : 0
  ami                         = nonsensitive(data.aws_ssm_parameter.ami[0].value)
  instance_type               = "t3.micro"
  subnet_id                   = aws_subnet.public[local.azs[0]].id
  vpc_security_group_ids      = [aws_security_group.proxy[0].id]
  associate_public_ip_address = true
  metadata_options { http_tokens = "required" }
  root_block_device { encrypted = true }
  user_data  = templatefile("${path.module}/proxy.sh.tftpl", { domains = join(" ", var.proxy_domains) })
  depends_on = [aws_route.internet]
}
resource "aws_cloudwatch_log_group" "flow" {
  count             = var.flow_logs ? 1 : 0
  name              = "/veriqta/${var.name}/flow"
  retention_in_days = 7
}
resource "aws_iam_role" "flow" {
  count = var.flow_logs ? 1 : 0
  name  = "${var.name}-flow"
  assume_role_policy = jsonencode({ Version = "2012-10-17", Statement = [{ Effect = "Allow", Action = "sts:AssumeRole", Principal = { Service = "vpc-flow-logs.amazonaws.com" }
  }] })
}
resource "aws_iam_role_policy" "flow" {
  count  = var.flow_logs ? 1 : 0
  role   = aws_iam_role.flow[0].id
  policy = jsonencode({ Version = "2012-10-17", Statement = [{ Effect = "Allow", Action = ["logs:CreateLogStream", "logs:PutLogEvents", "logs:DescribeLogStreams"], Resource = "${aws_cloudwatch_log_group.flow[0].arn}:*" }] })
}
resource "aws_flow_log" "this" {
  count           = var.flow_logs ? 1 : 0
  vpc_id          = aws_vpc.this.id
  traffic_type    = "ALL"
  iam_role_arn    = aws_iam_role.flow[0].arn
  log_destination = aws_cloudwatch_log_group.flow[0].arn
  depends_on      = [aws_iam_role_policy.flow]
}
output "vpc_id" { value = aws_vpc.this.id }
output "public_subnet_ids" { value = [for az in local.azs : aws_subnet.public[az].id] }
output "private_subnet_ids" { value = [for az in local.azs : aws_subnet.private[az].id] }
output "database_subnet_ids" { value = [for az in local.azs : aws_subnet.database[az].id] }
output "workload_security_group_id" { value = aws_security_group.workload.id }
output "database_cidrs" { value = local.database_cidrs }
output "proxy_private_ip" { value = try(aws_instance.proxy[0].private_ip, null) }
output "private_route_table_ids" {
  value = { for az, rt in aws_route_table.private : az => rt.id }
}
