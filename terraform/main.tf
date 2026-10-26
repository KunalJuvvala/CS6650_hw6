# Wire together the modules: network, ecr, logging, ecs (+ HW6: alb, autoscaling, dashboard).

module "network" {
  source         = "./modules/network"
  service_name   = var.service_name
  container_port = var.container_port
}

module "ecr" {
  source          = "./modules/ecr"
  repository_name = var.ecr_repository_name
}

module "logging" {
  source            = "./modules/logging"
  service_name      = var.service_name
  retention_in_days = var.log_retention_days
}

# Reuse an existing IAM role for ECS tasks
data "aws_iam_role" "lab_role" {
  name = "LabRole"
}

# HW6 Part III: Application Load Balancer + target group (only when enable_alb = true)
module "alb" {
  count          = var.enable_alb ? 1 : 0
  source         = "./modules/alb"
  service_name   = var.service_name
  vpc_id         = module.network.vpc_id
  subnet_ids     = module.network.subnet_ids
  container_port = var.container_port
}

module "ecs" {
  source             = "./modules/ecs"
  service_name       = var.service_name
  # Pin the task to the exact pushed digest: a new push => new task definition => ECS redeploys.
  image              = "${module.ecr.repository_url}@${docker_registry_image.app.sha256_digest}"
  container_port     = var.container_port
  subnet_ids         = module.network.subnet_ids
  security_group_ids = [module.network.security_group_id]
  execution_role_arn = data.aws_iam_role.lab_role.arn
  task_role_arn      = data.aws_iam_role.lab_role.arn
  log_group_name     = module.logging.log_group_name
  # With auto scaling on, start at the minimum; otherwise use the fixed count.
  ecs_count          = var.enable_autoscaling ? var.min_tasks : var.ecs_count
  region             = var.aws_region
  cpu                = var.task_cpu
  memory             = var.task_memory
  target_group_arn   = var.enable_alb ? module.alb[0].target_group_arn : null

  depends_on = [module.alb]
}

# HW6 Part III: target tracking on average CPU
module "autoscaling" {
  count              = var.enable_autoscaling ? 1 : 0
  source             = "./modules/autoscaling"
  cluster_name       = module.ecs.cluster_name
  service_name       = module.ecs.service_name
  min_tasks          = var.min_tasks
  max_tasks          = var.max_tasks
  cpu_target         = var.cpu_target
  scale_out_cooldown = var.scale_out_cooldown
  scale_in_cooldown  = var.scale_in_cooldown
}

# HW6: one CloudWatch dashboard with every infra metric the assignment asks for
module "dashboard" {
  source       = "./modules/dashboard"
  service_name = var.service_name
  region       = var.aws_region
  cluster_name = module.ecs.cluster_name
  ecs_service  = module.ecs.service_name
  alb_suffix   = var.enable_alb ? module.alb[0].alb_arn_suffix : ""
  tg_suffix    = var.enable_alb ? module.alb[0].target_group_arn_suffix : ""
  cpu_target   = var.cpu_target
}

// Build & push the Go app image into ECR.
// After changing Go code, force a rebuild + push + redeploy with:
//   terraform apply -replace=docker_image.app -replace=docker_registry_image.app
resource "docker_image" "app" {
  # Use the URL from the ecr module, and tag it "latest"
  name = "${module.ecr.repository_url}:latest"

  build {
    # relative path from terraform/ → src/
    context  = "../src"
    platform = "linux/amd64"
  }
}

resource "docker_registry_image" "app" {
  # this will push :latest → ECR
  name = docker_image.app.name
}
