# Region to deploy into
variable "aws_region" {
  type    = string
  default = "us-west-2"
}

# ECR & ECS settings
variable "ecr_repository_name" {
  type    = string
  default = "ecr_service"
}

variable "service_name" {
  type    = string
  default = "CS6650L2"
}

variable "container_port" {
  type    = number
  default = 8080
}

variable "ecs_count" {
  type    = number
  default = 1
}

# How long to keep logs
variable "log_retention_days" {
  type    = number
  default = 7
}

# ---------------------------------------------------------------------------
# HW6 additions
# ---------------------------------------------------------------------------

# Task size. Part II: 256 / 512. "Double the CPU" experiment: task_cpu = "512".
variable "task_cpu" {
  type    = string
  default = "256"
}

variable "task_memory" {
  type    = string
  default = "512"
}

# Part II: false (1 task, hit it directly on its public IP:8080)
# Part III: true  (ALB on port 80 in front of the tasks)
variable "enable_alb" {
  type    = bool
  default = false
}

# Part III: true (target-tracking on average CPU). Requires enable_alb = true.
variable "enable_autoscaling" {
  type    = bool
  default = false
}

variable "min_tasks" {
  type    = number
  default = 2
}

variable "max_tasks" {
  type    = number
  default = 4
}

variable "cpu_target" {
  type    = number
  default = 70
}

variable "scale_out_cooldown" {
  type    = number
  default = 300
}

variable "scale_in_cooldown" {
  type    = number
  default = 300
}
