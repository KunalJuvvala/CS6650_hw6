# Tells Application Auto Scaling it may change the service's DesiredCount between min and max.
resource "aws_appautoscaling_target" "ecs" {
  service_namespace  = "ecs"
  resource_id        = "service/${var.cluster_name}/${var.service_name}"
  scalable_dimension = "ecs:service:DesiredCount"
  min_capacity       = var.min_tasks
  max_capacity       = var.max_tasks
}

# Target tracking: keep the service's AVERAGE CPU around cpu_target %.
# AWS creates the two CloudWatch alarms (AlarmHigh / AlarmLow) for this automatically.
resource "aws_appautoscaling_policy" "cpu" {
  name               = "${var.service_name}-cpu-${var.cpu_target}"
  policy_type        = "TargetTrackingScaling"
  service_namespace  = aws_appautoscaling_target.ecs.service_namespace
  resource_id        = aws_appautoscaling_target.ecs.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs.scalable_dimension

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    target_value       = var.cpu_target
    scale_out_cooldown = var.scale_out_cooldown
    scale_in_cooldown  = var.scale_in_cooldown
  }
}
