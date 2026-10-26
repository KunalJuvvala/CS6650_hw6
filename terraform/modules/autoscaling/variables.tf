variable "cluster_name" { type = string }
variable "service_name" { type = string }
variable "min_tasks" { type = number }
variable "max_tasks" { type = number }
variable "cpu_target" { type = number }
variable "scale_out_cooldown" { type = number }
variable "scale_in_cooldown" { type = number }
