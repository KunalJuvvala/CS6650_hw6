output "alb_dns_name" {
  value = aws_lb.this.dns_name
}

output "alb_arn_suffix" {
  value = aws_lb.this.arn_suffix
}

output "target_group_arn" {
  # Depend on the listener so ECS only attaches once the TG is wired to the ALB.
  value = aws_lb_target_group.this.arn
  depends_on = [aws_lb_listener.http]
}

output "target_group_arn_suffix" {
  value = aws_lb_target_group.this.arn_suffix
}
