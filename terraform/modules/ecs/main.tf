# ECS Cluster
resource "aws_ecs_cluster" "this" {
  name = "${var.service_name}-cluster"

  # HW6: Container Insights gives RunningTaskCount / DesiredTaskCount in CloudWatch
  # (needed for "desired vs running task count" on the dashboard).
  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

# Task Definition
resource "aws_ecs_task_definition" "this" {
  family                   = "${var.service_name}-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.cpu
  memory                   = var.memory

  execution_role_arn = var.execution_role_arn
  task_role_arn      = var.task_role_arn

  container_definitions = jsonencode([{
    name      = "${var.service_name}-container"
    image     = var.image
    essential = true

    portMappings = [{
      containerPort = var.container_port
    }]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = var.log_group_name
        "awslogs-region"        = var.region
        "awslogs-stream-prefix" = "ecs"
      }
    }
  }])
}

# ECS Service
resource "aws_ecs_service" "this" {
  name            = var.service_name
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.this.arn
  desired_count   = var.ecs_count
  launch_type     = "FARGATE"

  # Only when an ALB is attached: give new tasks time to start before health checks count.
  health_check_grace_period_seconds = var.target_group_arn == null ? null : 60

  network_configuration {
    subnets          = var.subnet_ids
    security_groups  = var.security_group_ids
    # Kept on in Part III too, so Prometheus on your laptop can scrape each task directly.
    assign_public_ip = true
  }

  # HW6 Part III: register every task's IP in the ALB target group.
  dynamic "load_balancer" {
    for_each = var.target_group_arn == null ? [] : [var.target_group_arn]
    content {
      target_group_arn = load_balancer.value
      container_name   = "${var.service_name}-container"
      container_port   = var.container_port
    }
  }

  # NOTE: desired_count is NOT ignored on purpose. Every `terraform apply` resets the
  # service to min_tasks, which is a handy "reset" between experiments.
  # Don't run `terraform apply` WHILE a load test is running.
}
