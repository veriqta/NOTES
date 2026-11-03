mock_provider "aws" {
  source = "./tests"
}
variables {
  name = "veriqta-test"
}
run "security_contract" {
  command = plan
  assert {
    condition     = length(aws_subnet.private) == 2 && length(aws_subnet.database) == 2
    error_message = "Default network contract requires two AZs."
  }
  assert {
    condition     = alltrue([for r in aws_security_group.workload.egress : try(length(r.cidr_blocks), 0) == 0])
    error_message = "Workloads must not get direct CIDR-based internet egress."
  }
}

run "nat_does_not_open_egress" {
  command = plan
  variables {
    enable_nat = true
  }
  assert {
    condition     = length(aws_nat_gateway.this) == 2 && alltrue([for r in aws_security_group.workload.egress : try(length(r.cidr_blocks), 0) == 0])
    error_message = "Per-AZ NAT must not bypass workload egress restrictions."
  }
}
