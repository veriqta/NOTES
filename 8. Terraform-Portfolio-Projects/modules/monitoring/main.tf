variable "name" { type = string }
variable "alb_suffix" { type = string }
variable "target_group_suffix" { type = string }
variable "database_identifier" { type = string }
variable "asg_name" { type = string }
resource "aws_sns_topic" "alarms" { name = "${var.name}-alarms" }
resource "aws_cloudwatch_metric_alarm" "latency" {
  alarm_name          = "${var.name}-p95-latency"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "TargetResponseTime"
  dimensions          = { LoadBalancer = var.alb_suffix, TargetGroup = var.target_group_suffix }
  extended_statistic  = "p95"
  period              = 60
  evaluation_periods  = 3
  threshold           = 0.5
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "missing"
  alarm_actions       = [aws_sns_topic.alarms.arn]
}
resource "aws_cloudwatch_metric_alarm" "errors" {
  alarm_name          = "${var.name}-target-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  threshold           = 2
  treat_missing_data  = "missing"
  alarm_actions       = [aws_sns_topic.alarms.arn]
  metric_query {
    id          = "error_percent"
    expression  = "IF(requests>0,100*FILL(errors,0)/requests)"
    label       = "Target 5xx percent"
    return_data = true
  }
  metric_query {
    id = "requests"
    metric {
      namespace   = "AWS/ApplicationELB"
      metric_name = "RequestCount"
      period      = 60
      stat        = "Sum"
      dimensions  = { LoadBalancer = var.alb_suffix, TargetGroup = var.target_group_suffix }
    }
  }
  metric_query {
    id = "errors"
    metric {
      namespace   = "AWS/ApplicationELB"
      metric_name = "HTTPCode_Target_5XX_Count"
      period      = 60
      stat        = "Sum"
      dimensions  = { LoadBalancer = var.alb_suffix, TargetGroup = var.target_group_suffix }
    }
  }
}
resource "aws_cloudwatch_dashboard" "this" {
  dashboard_name = var.name
  dashboard_body = jsonencode({ widgets = [
    { type = "metric", x = 0, y = 0, width = 12, height = 6, properties = { title = "ALB request rate and errors", region = data.aws_region.current.region, metrics = [["AWS/ApplicationELB", "RequestCount", "LoadBalancer", var.alb_suffix], ["AWS/ApplicationELB", "HTTPCode_Target_5XX_Count", "LoadBalancer", var.alb_suffix]], stat = "Sum", period = 60 }
    },
    { type = "metric", x = 12, y = 0, width = 12, height = 6, properties = { title = "Database connections", region = data.aws_region.current.region, metrics = [["AWS/RDS", "DatabaseConnections", "DBInstanceIdentifier", var.database_identifier]], period = 60, stat = "Maximum" }
    },
    { type = "metric", x = 0, y = 6, width = 12, height = 6, properties = { title = "ASG capacity", region = data.aws_region.current.region, metrics = [["AWS/AutoScaling", "GroupInServiceInstances", "AutoScalingGroupName", var.asg_name], ["AWS/AutoScaling", "GroupDesiredCapacity", "AutoScalingGroupName", var.asg_name]], period = 60, stat = "Average" }
    },
    { type = "metric", x = 12, y = 6, width = 12, height = 6, properties = { title = "Memory percent (agent)", region = data.aws_region.current.region, metrics = [["Veriqta/Portfolio", "mem_used_percent", "AutoScalingGroupName", var.asg_name]], period = 60, stat = "Maximum" }
    }
  ] })
}
data "aws_region" "current" {}
output "alarm_topic_arn" { value = aws_sns_topic.alarms.arn }
