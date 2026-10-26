# Part II experiment: "could doubling CPU fix it?" (vertical scaling)
#   terraform apply -var-file=part2-double-cpu.tfvars
enable_alb         = false
enable_autoscaling = false
ecs_count          = 1
task_cpu           = "512"
task_memory        = "1024"
