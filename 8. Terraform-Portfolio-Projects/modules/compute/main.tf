variable "name" { type = string }
variable "region" { type = string }
variable "vpc_id" { type = string }
variable "private_subnet_ids" { type = list(string) }
variable "public_subnet_ids" { type = list(string) }
variable "workload_security_group_id" { type = string }
variable "ami_id" {
  type        = string
  description = "Baked x86_64 AMI built with application/prepare-image.sh; do not use an unprepared OS image."
  validation {
    condition     = can(regex("^ami-[0-9a-f]+$", var.ami_id))
    error_message = "Supply the reviewed regional application AMI."
  }
}
variable "secret_arn" { type = string }
variable "kms_key_arn" { type = string }
variable "db_host" { type = string }
variable "desired_capacity" {
  type    = number
  default = 6
  validation {
    condition     = var.desired_capacity >= var.minimum_capacity && var.desired_capacity <= var.maximum_capacity && var.desired_capacity == floor(var.desired_capacity)
    error_message = "Use at least three instances and an integer desired capacity."
  }
}
variable "instance_types" {
  type    = list(string)
  default = ["t3.small", "t3a.small"]
}
variable "minimum_capacity" {
  type    = number
  default = 3
}
variable "maximum_capacity" {
  type    = number
  default = 12
}
variable "ingress_cidrs" {
  type        = list(string)
  description = "Approved IPv4 client networks; use a narrow CIDR for the lab HTTP listener."
}
variable "certificate_arn" {
  type    = string
  default = null
}
resource "aws_security_group" "alb" {
  name_prefix = "${var.name}-alb-"
  vpc_id      = var.vpc_id
  ingress {
    from_port   = var.certificate_arn == null ? 80 : 443
    to_port     = var.certificate_arn == null ? 80 : 443
    protocol    = "tcp"
    cidr_blocks = var.ingress_cidrs
  }
  egress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"]
  }
}
resource "aws_security_group" "application" {
  name_prefix = "${var.name}-application-"
  vpc_id      = var.vpc_id
  ingress {
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }
  egress = []
}
resource "aws_cloudwatch_log_group" "application" {
  name              = "/veriqta/${var.name}/application"
  retention_in_days = 7
}
resource "aws_iam_role" "instance" {
  name = "${var.name}-instance"
  assume_role_policy = jsonencode({ Version = "2012-10-17", Statement = [{ Effect = "Allow", Action = "sts:AssumeRole", Principal = { Service = "ec2.amazonaws.com" }
  }] })
}
resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.instance.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}
resource "aws_iam_role_policy" "runtime" {
  role = aws_iam_role.instance.id
  policy = jsonencode({ Version = "2012-10-17", Statement = [
    { Effect = "Allow", Action = "secretsmanager:GetSecretValue", Resource = var.secret_arn },
    { Effect = "Allow", Action = "kms:Decrypt", Resource = var.kms_key_arn, Condition = { StringEquals = { "kms:ViaService" = "secretsmanager.${var.region}.amazonaws.com" }
    } },
    { Effect = "Allow", Action = ["logs:CreateLogStream", "logs:PutLogEvents", "logs:DescribeLogStreams"], Resource = "${aws_cloudwatch_log_group.application.arn}:*" },
    { Effect = "Allow", Action = "cloudwatch:PutMetricData", Resource = "*", Condition = { StringEquals = { "cloudwatch:namespace" = "Veriqta/Portfolio" }
    } },
    { Effect = "Allow", Action = "ec2:DescribeTags", Resource = "*" }
  ] })
}
resource "aws_iam_instance_profile" "this" {
  name = "${var.name}-instance"
  role = aws_iam_role.instance.name
}
resource "aws_lb" "this" {
  name                       = "${var.name}-alb"
  load_balancer_type         = "application"
  internal                   = false
  subnets                    = var.public_subnet_ids
  security_groups            = [aws_security_group.alb.id]
  drop_invalid_header_fields = true
}
resource "aws_lb_target_group" "this" {
  name     = "${var.name}-api"
  vpc_id   = var.vpc_id
  port     = 8080
  protocol = "HTTP"
  health_check {
    path     = "/readyz"
    matcher  = "200"
    interval = 30
    timeout  = 5
  }
}
resource "aws_lb_listener" "this" {
  load_balancer_arn = aws_lb.this.arn
  port              = var.certificate_arn == null ? 80 : 443
  protocol          = var.certificate_arn == null ? "HTTP" : "HTTPS"
  certificate_arn   = var.certificate_arn
  ssl_policy        = var.certificate_arn == null ? null : "ELBSecurityPolicy-TLS13-1-2-2021-06"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this.arn
  }
}
resource "aws_launch_template" "this" {
  name_prefix            = "${var.name}-"
  image_id               = var.ami_id
  vpc_security_group_ids = [aws_security_group.application.id, var.workload_security_group_id]
  iam_instance_profile { arn = aws_iam_instance_profile.this.arn }
  metadata_options {
    http_tokens                 = "required"
    http_endpoint               = "enabled"
    http_put_response_hop_limit = 1
  }
  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      encrypted             = true
      volume_type           = "gp3"
      volume_size           = 10
      delete_on_termination = true
    }
  }
  user_data = base64encode(templatefile("${path.module}/user-data.sh.tftpl", {
    region = var.region, secret_arn = var.secret_arn, db_host = var.db_host, log_group = aws_cloudwatch_log_group.application.name
  }))
}
resource "aws_autoscaling_group" "this" {
  name                      = "${var.name}-asg"
  min_size                  = var.minimum_capacity
  max_size                  = var.maximum_capacity
  desired_capacity          = var.desired_capacity
  vpc_zone_identifier       = var.private_subnet_ids
  health_check_type         = "ELB"
  health_check_grace_period = 300
  target_group_arns         = [aws_lb_target_group.this.arn]
  enabled_metrics           = ["GroupDesiredCapacity", "GroupInServiceInstances"]
  mixed_instances_policy {
    instances_distribution {
      on_demand_base_capacity                  = var.minimum_capacity
      on_demand_percentage_above_base_capacity = 100
    }
    launch_template {
      launch_template_specification {
        launch_template_id = aws_launch_template.this.id
        version            = tostring(aws_launch_template.this.latest_version)
      }
      dynamic "override" {
        for_each = var.instance_types
        content { instance_type = override.value }
      }
    }
  }
  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 100
      max_healthy_percentage = 150
      instance_warmup        = 180
    }
  }
  lifecycle {
    ignore_changes = [desired_capacity]
    precondition {
      condition     = var.minimum_capacity <= var.desired_capacity && var.desired_capacity <= var.maximum_capacity
      error_message = "Require minimum <= desired <= maximum."
    }
  }
  tag {
    key                 = "Name"
    value               = var.name
    propagate_at_launch = true
  }
  depends_on = [aws_lb_listener.this, aws_iam_role_policy.runtime, aws_iam_role_policy_attachment.ssm]
}
resource "aws_autoscaling_policy" "cpu" {
  name                   = "${var.name}-cpu"
  autoscaling_group_name = aws_autoscaling_group.this.name
  policy_type            = "TargetTrackingScaling"
  target_tracking_configuration {
    predefined_metric_specification { predefined_metric_type = "ASGAverageCPUUtilization" }
    target_value = 50
  }
}
output "asg_name" { value = aws_autoscaling_group.this.name }
output "alb_arn_suffix" { value = aws_lb.this.arn_suffix }
output "alb_dns" { value = aws_lb.this.dns_name }
output "alb_zone_id" { value = aws_lb.this.zone_id }
output "target_group_arn" { value = aws_lb_target_group.this.arn }
output "target_group_suffix" { value = aws_lb_target_group.this.arn_suffix }
