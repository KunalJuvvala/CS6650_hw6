output "ecs_cluster_name" {
  description = "Name of the created ECS cluster"
  value       = module.ecs.cluster_name
}

output "ecs_service_name" {
  description = "Name of the running ECS service"
  value       = module.ecs.service_name
}

output "alb_url" {
  description = "Use this as the Locust --host in Part III"
  value       = var.enable_alb ? "http://${module.alb[0].alb_dns_name}" : "(ALB disabled - Part II mode)"
}

output "cloudwatch_dashboard_url" {
  value = module.dashboard.url
}
