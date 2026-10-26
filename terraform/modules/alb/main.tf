# Security group for the ALB: the internet can reach it on port 80.
# (The tasks' own SG already allows 8080 from anywhere, so ALB -> task traffic is allowed.)
resource "aws_security_group" "alb" {
  name        = "${var.service_name}-alb-sg"
  description = "Allow HTTP 80 to the ALB"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_lb" "this" {
  name               = substr(lower("${var.service_name}-alb"), 0, 32)
  load_balancer_type = "application"
  internal           = false
  security_groups    = [aws_security_group.alb.id]
  subnets            = var.subnet_ids
}

# Target group exactly as the assignment specifies.
resource "aws_lb_target_group" "this" {
  name        = substr(lower("${var.service_name}-tg"), 0, 32)
  target_type = "ip"   # required for Fargate (awsvpc)
  protocol    = "HTTP"
  port        = var.container_port
  vpc_id      = var.vpc_id

  # Default is 300 s; 30 s makes stopped / scaled-in tasks leave quickly so experiments are faster.
  deregistration_delay = 30

  health_check {
    path                = "/health"
    interval            = 30
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 5
    matcher             = "200"
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this.arn
  }
}
