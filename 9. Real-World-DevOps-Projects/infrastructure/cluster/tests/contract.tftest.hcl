mock_provider "aws" {
  source = "./tests"
}
variables {
  account_id             = "123456789012"
  region                 = "us-east-1"
  name                   = "veriqta-test"
  kubernetes_version     = "1.34"
  administrator_role_arn = "arn:aws:iam::123456789012:role/veriqta-operator"
  administrator_cidrs    = ["192.0.2.0/24"]
  foundation             = { vpc_id = "vpc-0123456789abcdef0", private_subnet_ids = ["subnet-0123456789abcdef0", "subnet-0123456789abcdef1", "subnet-0123456789abcdef2"], workload_sg_id = "sg-0123456789abcdef0", secret_arn = "arn:aws:secretsmanager:us-east-1:123456789012:secret:veriqta-AbCdEf", kms_key_arn = "arn:aws:kms:us-east-1:123456789012:key/00000000-0000-0000-0000-000000000000", queue_arn = "arn:aws:sqs:us-east-1:123456789012:veriqta-jobs" }
}
run "contract" {
  command = plan
  assert {
    condition     = aws_eks_cluster.this.vpc_config[0].endpoint_private_access && aws_eks_node_group.this.scaling_config[0].min_size == 3
    error_message = "Private control-plane access and initial three-node capacity are required."
  }
  assert {
    condition     = aws_eks_cluster.this.access_config[0].bootstrap_cluster_creator_admin_permissions == false
    error_message = "Cluster administration must use the explicit access entry."
  }
}
