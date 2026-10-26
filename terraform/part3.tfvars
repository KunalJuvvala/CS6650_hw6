# Part III core test: ALB + target tracking at 70% CPU, 2..4 tasks, 300 s cooldowns.
#   terraform apply -var-file=part3.tfvars
# Exploration: override on the command line, e.g.
#   terraform apply -var-file=part3.tfvars -var cpu_target=50
#   terraform apply -var-file=part3.tfvars -var scale_out_cooldown=60 -var scale_in_cooldown=60
#   terraform apply -var-file=part3.tfvars -var min_tasks=1 -var max_tasks=6
enable_alb         = true
enable_autoscaling = true
task_cpu           = "256"
task_memory        = "512"
min_tasks          = 2
max_tasks          = 4
cpu_target         = 70
scale_out_cooldown = 300
scale_in_cooldown  = 300
