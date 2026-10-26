# Part II: one 0.25 vCPU / 512 MB task, no ALB, no auto scaling.
#   terraform apply -var-file=part2.tfvars
enable_alb         = false
enable_autoscaling = false
ecs_count          = 1
task_cpu           = "256"
task_memory        = "512"
