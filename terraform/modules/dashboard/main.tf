# One CloudWatch dashboard with the infra view the assignment asks for.
# ALB panels are only added when an ALB exists (Part III).
locals {
  name    = "${var.service_name}-hw6"
  has_alb = var.alb_suffix != ""
  svc     = ["ClusterName", var.cluster_name, "ServiceName", var.ecs_service]

  ecs_widgets = [
    {
      type = "metric", x = 0, y = 0, width = 12, height = 6
      properties = {
        title   = "ECS service CPU % (avg & max across tasks)"
        region  = var.region, view = "timeSeries", period = 60
        metrics = [
          concat(["AWS/ECS", "CPUUtilization"], local.svc, [{ stat = "Average", label = "CPU avg" }]),
          concat(["AWS/ECS", "CPUUtilization"], local.svc, [{ stat = "Maximum", label = "CPU max" }]),
        ]
        yAxis       = { left = { min = 0, max = 100 } }
        annotations = { horizontal = [{ value = var.cpu_target, label = "scaling target" }] }
      }
    },
    {
      type = "metric", x = 12, y = 0, width = 12, height = 6
      properties = {
        title   = "ECS service Memory %"
        region  = var.region, view = "timeSeries", period = 60
        metrics = [
          concat(["AWS/ECS", "MemoryUtilization"], local.svc, [{ stat = "Average", label = "Mem avg" }]),
          concat(["AWS/ECS", "MemoryUtilization"], local.svc, [{ stat = "Maximum", label = "Mem max" }]),
        ]
        yAxis = { left = { min = 0, max = 100 } }
      }
    },
    {
      type = "metric", x = 0, y = 6, width = 12, height = 6
      properties = {
        title   = "Tasks: desired vs running vs pending (Container Insights)"
        region  = var.region, view = "timeSeries", period = 60, stat = "Average"
        metrics = [
          concat(["ECS/ContainerInsights", "DesiredTaskCount"], local.svc),
          concat(["ECS/ContainerInsights", "RunningTaskCount"], local.svc),
          concat(["ECS/ContainerInsights", "PendingTaskCount"], local.svc),
        ]
        yAxis = { left = { min = 0 } }
      }
    },
  ]

  alb_widgets_all = [
    {
      type = "metric", x = 12, y = 6, width = 12, height = 6
      properties = {
        title   = "ALB request count (per minute)"
        region  = var.region, view = "timeSeries", period = 60, stat = "Sum"
        metrics = [
          ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", var.alb_suffix],
          ["AWS/ApplicationELB", "RequestCountPerTarget", "TargetGroup", var.tg_suffix, "LoadBalancer", var.alb_suffix],
        ]
      }
    },
    {
      type = "metric", x = 0, y = 12, width = 12, height = 6
      properties = {
        title   = "ALB target response time (seconds)"
        region  = var.region, view = "timeSeries", period = 60
        metrics = [
          ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", var.alb_suffix, { stat = "p50", label = "p50" }],
          ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", var.alb_suffix, { stat = "p95", label = "p95" }],
          ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", var.alb_suffix, { stat = "Average", label = "avg" }],
        ]
      }
    },
    {
      type = "metric", x = 12, y = 12, width = 12, height = 6
      properties = {
        title   = "Target group health + 5xx"
        region  = var.region, view = "timeSeries", period = 60
        metrics = [
          ["AWS/ApplicationELB", "HealthyHostCount", "TargetGroup", var.tg_suffix, "LoadBalancer", var.alb_suffix, { stat = "Minimum" }],
          ["AWS/ApplicationELB", "UnHealthyHostCount", "TargetGroup", var.tg_suffix, "LoadBalancer", var.alb_suffix, { stat = "Maximum" }],
          ["AWS/ApplicationELB", "HTTPCode_ELB_5XX_Count", "LoadBalancer", var.alb_suffix, { stat = "Sum", yAxis = "right" }],
          ["AWS/ApplicationELB", "HTTPCode_Target_5XX_Count", "LoadBalancer", var.alb_suffix, { stat = "Sum", yAxis = "right" }],
        ]
      }
    },
  ]

  # slice() instead of a ternary avoids Terraform's "inconsistent conditional types" error.
  alb_widgets = slice(local.alb_widgets_all, 0, local.has_alb ? length(local.alb_widgets_all) : 0)
}

resource "aws_cloudwatch_dashboard" "this" {
  dashboard_name = local.name
  dashboard_body = jsonencode({ widgets = concat(local.ecs_widgets, local.alb_widgets) })
}
