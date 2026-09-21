resource "aws_cloudwatch_log_group" "this" {
  name              = "/aws/ecs/${var.name}"
  retention_in_days = var.log_retention_days
  tags              = local.common_tags
}

resource "aws_ecs_cluster" "this" {
  name = var.name
  tags = local.common_tags
}

resource "aws_ecs_task_definition" "this" {
  family                   = var.name
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = tostring(var.cpu)
  memory                   = tostring(var.memory)
  execution_role_arn       = aws_iam_role.task_execution.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  container_definitions = jsonencode([
    {
      name      = local.relay_container_name
      image     = var.image
      essential = true

      environment = [
        {
          name  = "NB_LOG_LEVEL"
          value = "info"
        },
        {
          name  = "NB_LISTEN_ADDRESS"
          value = ":${local.relay_container_port}"
        },
        {
          name  = "NB_EXPOSED_ADDRESS"
          value = local.relay_uri
        },
        {
          name  = "NB_ENABLE_STUN"
          value = "true"
        },
        {
          name  = "NB_STUN_PORTS"
          value = tostring(local.stun_container_port)
        },
      ]

      secrets = [
        {
          name      = "NB_AUTH_SECRET"
          valueFrom = "${var.relay_auth_secret_arn}:::${local.relay_auth_secret_current_version_id}"
        },
      ]

      portMappings = [
        {
          name          = "relay"
          containerPort = local.relay_container_port
          hostPort      = local.relay_container_port
          protocol      = "tcp"
        },
        {
          name          = "stun"
          containerPort = local.stun_container_port
          hostPort      = local.stun_container_port
          protocol      = "udp"
        },
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.this.name
          awslogs-region        = local.aws_region
          awslogs-stream-prefix = "relay"
        }
      }
    },
  ])

  tags = local.common_tags

  lifecycle {
    precondition {
      condition     = local.valid_fargate_size
      error_message = "The cpu and memory values must form a supported Fargate task size."
    }
  }
}

resource "aws_ecs_service" "this" {
  name             = var.name
  cluster          = aws_ecs_cluster.this.arn
  task_definition  = aws_ecs_task_definition.this.arn
  desired_count    = 1
  launch_type      = "FARGATE"
  platform_version = "1.4.0"

  deployment_minimum_healthy_percent = 0
  deployment_maximum_percent         = 100
  health_check_grace_period_seconds  = 30
  propagate_tags                     = "SERVICE"

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  network_configuration {
    assign_public_ip = false
    subnets          = var.private_subnet_ids
    security_groups  = [aws_security_group.task.id]
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.relay.arn
    container_name   = local.relay_container_name
    container_port   = local.relay_container_port
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.stun.arn
    container_name   = local.relay_container_name
    container_port   = local.stun_container_port
  }

  tags = local.common_tags

  depends_on = [
    aws_iam_role_policy_attachment.task_execution,
    aws_iam_role_policy.relay_secret,
    aws_lb_listener.relay,
    aws_lb_listener.stun,
  ]
}
