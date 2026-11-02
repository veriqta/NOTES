variable "approved_cidr" {
  type    = string
  default = "10.90.0.0/16"
  validation {
    condition     = can(cidrhost(var.approved_cidr, 0))
    error_message = "Supply a valid approved CIDR."
  }
}
resource "aws_vpc" "lab" { cidr_block = "10.90.0.0/16" }
resource "aws_security_group" "lab" {
  name_prefix = "${var.name}-"
  vpc_id      = aws_vpc.lab.id
  description = "Unattached drift exercise; never attach this group to a workload"
}
resource "aws_vpc_security_group_ingress_rule" "https" {
  security_group_id = aws_security_group.lab.id
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = var.approved_cidr
}
output "group_id" { value = aws_security_group.lab.id }
output "group_arn" { value = aws_security_group.lab.arn }
output "rule_id" { value = aws_vpc_security_group_ingress_rule.https.id }
