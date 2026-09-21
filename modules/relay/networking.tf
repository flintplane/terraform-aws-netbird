resource "aws_security_group" "load_balancer" {
  name_prefix = "${var.name}-nlb-"
  description = "Public ingress to the ${var.name} NetBird Relay and STUN endpoint"
  vpc_id      = var.vpc_id

  ingress {
    description = "NetBird Relay over TLS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "NetBird STUN"
    from_port   = local.stun_container_port
    to_port     = local.stun_container_port
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Forward traffic to relay tasks"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = local.common_tags

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group" "task" {
  name_prefix = "${var.name}-task-"
  description = "Traffic from the ${var.name} Network Load Balancer to the Relay task"
  vpc_id      = var.vpc_id

  ingress {
    description     = "Relay traffic and health checks from the NLB"
    from_port       = local.relay_container_port
    to_port         = local.relay_container_port
    protocol        = "tcp"
    security_groups = [aws_security_group.load_balancer.id]
  }

  ingress {
    description     = "STUN traffic from the NLB"
    from_port       = local.stun_container_port
    to_port         = local.stun_container_port
    protocol        = "udp"
    security_groups = [aws_security_group.load_balancer.id]
  }

  egress {
    description = "Task runtime dependencies"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = local.common_tags

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_lb" "this" {
  name                             = var.name
  internal                         = false
  load_balancer_type               = "network"
  subnets                          = var.public_subnet_ids
  security_groups                  = [aws_security_group.load_balancer.id]
  enable_cross_zone_load_balancing = true

  tags = local.common_tags
}

resource "aws_lb_target_group" "relay" {
  name_prefix = "relay-"
  port        = local.relay_container_port
  protocol    = "TCP"
  target_type = "ip"
  vpc_id      = var.vpc_id

  deregistration_delay = 30
  preserve_client_ip   = true

  health_check {
    enabled             = true
    protocol            = "TCP"
    port                = "traffic-port"
    healthy_threshold   = 3
    unhealthy_threshold = 3
    interval            = 10
  }

  tags = local.common_tags

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_lb_target_group" "stun" {
  name_prefix = "stun-"
  port        = local.stun_container_port
  protocol    = "UDP"
  target_type = "ip"
  vpc_id      = var.vpc_id

  deregistration_delay = 30

  health_check {
    enabled             = true
    protocol            = "TCP"
    port                = tostring(local.relay_container_port)
    healthy_threshold   = 3
    unhealthy_threshold = 3
    interval            = 10
  }

  tags = local.common_tags

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_lb_listener" "relay" {
  load_balancer_arn = aws_lb.this.arn
  port              = 443
  protocol          = "TLS"
  certificate_arn   = var.certificate_arn
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.relay.arn
  }

  tags = local.common_tags
}

resource "aws_lb_listener" "stun" {
  load_balancer_arn = aws_lb.this.arn
  port              = local.stun_container_port
  protocol          = "UDP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.stun.arn
  }

  tags = local.common_tags
}

resource "aws_route53_record" "this" {
  zone_id = var.route53_zone_id
  name    = var.fqdn
  type    = "A"

  alias {
    name                   = aws_lb.this.dns_name
    zone_id                = aws_lb.this.zone_id
    evaluate_target_health = true
  }
}
