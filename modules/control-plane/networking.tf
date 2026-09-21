data "aws_subnet" "load_balancer" {
  for_each = var.public_subnet_ids

  id = each.value
}

resource "aws_security_group" "load_balancer" {
  name_prefix = "${var.name}-alb-"
  description = "Public HTTPS ingress to the ${var.name} NetBird control plane"
  vpc_id      = var.vpc_id

  ingress {
    description      = "HTTPS"
    from_port        = 443
    to_port          = 443
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = var.enable_ipv6 ? ["::/0"] : []
  }

  tags = local.common_tags

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group" "management" {
  name_prefix = "${var.name}-management-"
  description = "Traffic to the ${var.name} NetBird Management task"
  vpc_id      = var.vpc_id

  egress {
    description = "Runtime dependencies and identity provider"
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

resource "aws_security_group" "signal" {
  name_prefix = "${var.name}-signal-"
  description = "Traffic to the ${var.name} NetBird Signal task"
  vpc_id      = var.vpc_id

  egress {
    description = "Runtime dependencies"
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

resource "aws_security_group" "dashboard" {
  name_prefix = "${var.name}-dashboard-"
  description = "Traffic to the ${var.name} NetBird Dashboard task"
  vpc_id      = var.vpc_id

  egress {
    description = "Runtime dependencies"
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

resource "aws_security_group" "database" {
  name_prefix = "${var.name}-database-"
  description = "PostgreSQL access from the ${var.name} NetBird Management task"
  vpc_id      = var.vpc_id

  ingress {
    description     = "PostgreSQL from Management"
    from_port       = local.database_port
    to_port         = local.database_port
    protocol        = "tcp"
    security_groups = [aws_security_group.management.id]
  }

  tags = local.common_tags

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "service_from_load_balancer" {
  for_each = {
    management = aws_security_group.management.id
    signal     = aws_security_group.signal.id
    dashboard  = aws_security_group.dashboard.id
  }

  security_group_id            = each.value
  referenced_security_group_id = aws_security_group.load_balancer.id
  description                  = "Application traffic from the ALB"
  from_port                    = local.application_port
  to_port                      = local.application_port
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "load_balancer_to_service" {
  for_each = {
    management = aws_security_group.management.id
    signal     = aws_security_group.signal.id
    dashboard  = aws_security_group.dashboard.id
  }

  security_group_id            = aws_security_group.load_balancer.id
  referenced_security_group_id = each.value
  description                  = "Application traffic to the ${each.key} task"
  from_port                    = local.application_port
  to_port                      = local.application_port
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "signal_grpc_from_load_balancer" {
  security_group_id            = aws_security_group.signal.id
  referenced_security_group_id = aws_security_group.load_balancer.id
  description                  = "Native gRPC traffic from the ALB"
  from_port                    = local.signal_grpc_port
  to_port                      = local.signal_grpc_port
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "load_balancer_to_signal_grpc" {
  security_group_id            = aws_security_group.load_balancer.id
  referenced_security_group_id = aws_security_group.signal.id
  description                  = "Native gRPC traffic to the Signal task"
  from_port                    = local.signal_grpc_port
  to_port                      = local.signal_grpc_port
  ip_protocol                  = "tcp"
}

resource "aws_lb" "this" {
  name               = var.name
  internal           = false
  load_balancer_type = "application"
  ip_address_type    = var.enable_ipv6 ? "dualstack" : "ipv4"
  subnets            = var.public_subnet_ids
  security_groups    = [aws_security_group.load_balancer.id]
  idle_timeout       = 4000

  tags = local.common_tags
}

resource "aws_lb_target_group" "management_http" {
  name_prefix = "mhttp-"
  port        = local.application_port
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = var.vpc_id

  protocol_version     = "HTTP1"
  deregistration_delay = 30

  health_check {
    enabled             = true
    protocol            = "HTTP"
    path                = "/api/instance"
    matcher             = "200-399"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 15
    timeout             = 5
  }

  tags = local.common_tags

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_lb_target_group" "management_grpc" {
  name_prefix = "mgrpc-"
  port        = local.application_port
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = var.vpc_id

  protocol_version     = "GRPC"
  deregistration_delay = 30

  health_check {
    enabled             = true
    protocol            = "HTTP"
    path                = "/management.ManagementService/isHealthy"
    matcher             = "0"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 15
    timeout             = 5
  }

  tags = local.common_tags

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_lb_target_group" "signal_http" {
  name_prefix = "shttp-"
  port        = local.application_port
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = var.vpc_id

  protocol_version     = "HTTP1"
  deregistration_delay = 30

  health_check {
    enabled             = true
    protocol            = "HTTP"
    path                = "/"
    matcher             = "200-499"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 15
    timeout             = 5
  }

  tags = local.common_tags

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_lb_target_group" "signal_grpc" {
  name_prefix = "sgrpc-"
  port        = local.signal_grpc_port
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = var.vpc_id

  protocol_version     = "GRPC"
  deregistration_delay = 30

  health_check {
    enabled             = true
    protocol            = "HTTP"
    path                = "/AWS.ALB/healthcheck"
    matcher             = "12"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 15
    timeout             = 5
  }

  tags = local.common_tags

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_lb_target_group" "dashboard" {
  name_prefix = "dash-"
  port        = local.application_port
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = var.vpc_id

  protocol_version     = "HTTP1"
  deregistration_delay = 30

  health_check {
    enabled             = true
    protocol            = "HTTP"
    path                = "/"
    matcher             = "200-399"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 15
    timeout             = 5
  }

  tags = local.common_tags

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.this.arn
  port              = 443
  protocol          = "HTTPS"
  certificate_arn   = var.certificate_arn
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"

  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/plain"
      message_body = "Not found"
      status_code  = "404"
    }
  }

  tags = local.common_tags
}

resource "aws_lb_listener_rule" "management_grpc" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 10

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.management_grpc.arn
  }

  condition {
    host_header {
      values = [var.endpoints.management_fqdn]
    }
  }

  condition {
    path_pattern {
      values = ["/management.ManagementService/*", "/management.ProxyService/*"]
    }
  }
}

resource "aws_lb_listener_rule" "management_http" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 20

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.management_http.arn
  }

  condition {
    host_header {
      values = [var.endpoints.management_fqdn]
    }
  }
}

resource "aws_lb_listener_rule" "signal_http" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 30

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.signal_http.arn
  }

  condition {
    host_header {
      values = [var.endpoints.signal_fqdn]
    }
  }

  condition {
    path_pattern {
      values = ["/ws-proxy/signal*"]
    }
  }
}

resource "aws_lb_listener_rule" "signal_grpc" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 40

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.signal_grpc.arn
  }

  condition {
    host_header {
      values = [var.endpoints.signal_fqdn]
    }
  }
}

resource "aws_lb_listener_rule" "dashboard" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 50

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.dashboard.arn
  }

  condition {
    host_header {
      values = [var.endpoints.dashboard_fqdn]
    }
  }
}

resource "aws_route53_record" "endpoints" {
  for_each = toset([
    var.endpoints.management_fqdn,
    var.endpoints.signal_fqdn,
    var.endpoints.dashboard_fqdn,
  ])

  zone_id = var.route53_zone_id
  name    = each.value
  type    = "A"

  alias {
    name                   = aws_lb.this.dns_name
    zone_id                = aws_lb.this.zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "ipv6_endpoints" {
  for_each = var.enable_ipv6 ? toset([
    var.endpoints.management_fqdn,
    var.endpoints.signal_fqdn,
    var.endpoints.dashboard_fqdn,
  ]) : toset([])

  zone_id = var.route53_zone_id
  name    = each.value
  type    = "AAAA"

  alias {
    name                   = aws_lb.this.dns_name
    zone_id                = aws_lb.this.zone_id
    evaluate_target_health = true
  }
}
