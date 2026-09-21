resource "aws_cloudwatch_log_group" "service" {
  for_each = toset(["management", "signal", "dashboard"])

  name              = "/aws/ecs/${var.name}/${each.key}"
  retention_in_days = var.log_retention_days
  tags              = local.common_tags
}

resource "aws_ecs_cluster" "this" {
  name = var.name
  tags = local.common_tags
}

data "aws_secretsmanager_secret_versions" "relay_auth" {
  secret_id = var.relay.auth_secret_arn
}

resource "aws_ecs_task_definition" "management" {
  family                   = "${var.name}-management"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = tostring(var.service_resources.management.cpu)
  memory                   = tostring(var.service_resources.management.memory)
  execution_role_arn       = aws_iam_role.task_execution["management"].arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  container_definitions = jsonencode([
    {
      name      = local.management_container_name
      image     = var.images.management
      essential = true

      entryPoint = ["/bin/sh", "-c"]
      command = [<<-EOT
        set -eu
        export NETBIRD_POSTGRES_DSN="host=$DB_HOST port=$DB_PORT user=$DB_USERNAME password=$DB_PASSWORD dbname=$DB_NAME sslmode=require"
        export NETBIRD_STORE_ENGINE_POSTGRES_DSN="$NETBIRD_POSTGRES_DSN"
        export NB_ACTIVITY_EVENT_STORE_ENGINE="postgres"
        export NB_ACTIVITY_EVENT_POSTGRES_DSN="$NETBIRD_POSTGRES_DSN"
        export NETBIRD_AUTH_POSTGRES_DSN="$NETBIRD_POSTGRES_DSN"
        mkdir -p /etc/netbird
        printf '%s' "$NETBIRD_MANAGEMENT_CONFIG" > /etc/netbird/management.json
        exec /go/bin/netbird-mgmt management \
          --config /etc/netbird/management.json \
          --port ${local.application_port} \
          --log-file console \
          --log-level info \
          --disable-anonymous-metrics=true \
          --single-account-mode-domain=${var.single_account_mode_domain} \
          --dns-domain=${var.netbird_dns_domain}
      EOT
      ]

      environment = [
        {
          name  = "DB_HOST"
          value = aws_db_instance.this.address
        },
        {
          name  = "DB_PORT"
          value = tostring(local.database_port)
        },
        {
          name  = "DB_NAME"
          value = local.database_name
        },
        {
          name  = "DB_USERNAME"
          value = local.database_username
        },
        {
          name  = "NETBIRD_MANAGEMENT_CONFIG"
          value = jsonencode(local.management_config)
        },
      ]

      secrets = [
        {
          name      = "DB_PASSWORD"
          valueFrom = "${aws_secretsmanager_secret.database.arn}:::${aws_secretsmanager_secret_version.database.version_id}"
        },
        {
          name      = "NETBIRD_DATASTORE_ENC_KEY"
          valueFrom = "${aws_secretsmanager_secret.datastore_encryption_key.arn}:::${aws_secretsmanager_secret_version.datastore_encryption_key.version_id}"
        },
        {
          name      = "NB_IDP_SESSION_COOKIE_ENCRYPTION_KEY"
          valueFrom = "${aws_secretsmanager_secret.session_cookie_encryption_key.arn}:::${aws_secretsmanager_secret_version.session_cookie_encryption_key.version_id}"
        },
        {
          name      = "NETBIRD_RELAY_AUTH_SECRET"
          valueFrom = "${var.relay.auth_secret_arn}:::${local.relay_auth_secret_current_version_id}"
        },
      ]

      portMappings = [
        {
          name          = "management"
          containerPort = local.application_port
          hostPort      = local.application_port
          protocol      = "tcp"
        },
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.service["management"].name
          awslogs-region        = local.aws_region
          awslogs-stream-prefix = "management"
        }
      }
    },
  ])

  tags = local.common_tags

  depends_on = [
    aws_secretsmanager_secret_version.database,
    aws_secretsmanager_secret_version.datastore_encryption_key,
    aws_secretsmanager_secret_version.session_cookie_encryption_key,
  ]

  lifecycle {
    precondition {
      condition     = local.valid_fargate_sizes.management
      error_message = "Management cpu and memory must form a supported Fargate task size."
    }

    precondition {
      condition     = split(":", var.relay.auth_secret_arn)[3] == local.aws_region
      error_message = "The Relay authentication secret must be in the same AWS region as the ACM certificate and control plane."
    }
  }
}

resource "aws_ecs_task_definition" "signal" {
  family                   = "${var.name}-signal"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = tostring(var.service_resources.signal.cpu)
  memory                   = tostring(var.service_resources.signal.memory)
  execution_role_arn       = aws_iam_role.task_execution["signal"].arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  container_definitions = jsonencode([
    {
      name      = local.signal_container_name
      image     = var.images.signal
      essential = true

      command = [
        "--port", tostring(local.application_port),
        "--log-file", "console",
        "--log-level", "info",
      ]

      portMappings = [
        {
          name          = "signal"
          containerPort = local.application_port
          hostPort      = local.application_port
          protocol      = "tcp"
        },
        {
          name          = "signal-grpc"
          containerPort = local.signal_grpc_port
          hostPort      = local.signal_grpc_port
          protocol      = "tcp"
        },
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.service["signal"].name
          awslogs-region        = local.aws_region
          awslogs-stream-prefix = "signal"
        }
      }
    },
  ])

  tags = local.common_tags

  lifecycle {
    precondition {
      condition     = local.valid_fargate_sizes.signal
      error_message = "Signal cpu and memory must form a supported Fargate task size."
    }
  }
}

resource "aws_ecs_task_definition" "dashboard" {
  family                   = "${var.name}-dashboard"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = tostring(var.service_resources.dashboard.cpu)
  memory                   = tostring(var.service_resources.dashboard.memory)
  execution_role_arn       = aws_iam_role.task_execution["dashboard"].arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  container_definitions = jsonencode([
    {
      name      = local.dashboard_container_name
      image     = var.images.dashboard
      essential = true

      environment = [
        {
          name  = "NETBIRD_MGMT_API_ENDPOINT"
          value = local.management_url
        },
        {
          name  = "NETBIRD_MGMT_GRPC_API_ENDPOINT"
          value = local.management_url
        },
        {
          name  = "AUTH_AUDIENCE"
          value = "netbird-dashboard"
        },
        {
          name  = "AUTH_CLIENT_ID"
          value = "netbird-dashboard"
        },
        {
          name  = "AUTH_CLIENT_SECRET"
          value = ""
        },
        {
          name  = "AUTH_AUTHORITY"
          value = local.auth_issuer
        },
        {
          name  = "USE_AUTH0"
          value = "false"
        },
        {
          name  = "AUTH_SUPPORTED_SCOPES"
          value = "openid profile email groups"
        },
        {
          name  = "AUTH_REDIRECT_URI"
          value = "/nb-auth"
        },
        {
          name  = "AUTH_SILENT_REDIRECT_URI"
          value = "/nb-silent-auth"
        },
        {
          name  = "NETBIRD_TOKEN_SOURCE"
          value = "accessToken"
        },
        {
          name  = "NGINX_SSL_PORT"
          value = "443"
        },
        {
          name  = "LETSENCRYPT_DOMAIN"
          value = "none"
        },
        {
          name  = "LETSENCRYPT_EMAIL"
          value = ""
        },
      ]

      portMappings = [
        {
          name          = "dashboard"
          containerPort = local.application_port
          hostPort      = local.application_port
          protocol      = "tcp"
        },
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.service["dashboard"].name
          awslogs-region        = local.aws_region
          awslogs-stream-prefix = "dashboard"
        }
      }
    },
  ])

  tags = local.common_tags

  lifecycle {
    precondition {
      condition     = local.valid_fargate_sizes.dashboard
      error_message = "Dashboard cpu and memory must form a supported Fargate task size."
    }
  }
}

resource "aws_ecs_service" "management" {
  name             = "${var.name}-management"
  cluster          = aws_ecs_cluster.this.arn
  task_definition  = aws_ecs_task_definition.management.arn
  desired_count    = 1
  launch_type      = "FARGATE"
  platform_version = "1.4.0"

  deployment_minimum_healthy_percent = 0
  deployment_maximum_percent         = 100
  health_check_grace_period_seconds  = 60
  propagate_tags                     = "SERVICE"

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  network_configuration {
    assign_public_ip = false
    subnets          = var.private_subnet_ids
    security_groups  = [aws_security_group.management.id]
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.management_http.arn
    container_name   = local.management_container_name
    container_port   = local.application_port
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.management_grpc.arn
    container_name   = local.management_container_name
    container_port   = local.application_port
  }

  tags = local.common_tags

  depends_on = [
    aws_iam_role_policy_attachment.task_execution,
    aws_iam_role_policy.management_secrets,
    aws_lb_listener_rule.management_grpc,
    aws_lb_listener_rule.management_http,
  ]
}

resource "aws_ecs_service" "signal" {
  name             = "${var.name}-signal"
  cluster          = aws_ecs_cluster.this.arn
  task_definition  = aws_ecs_task_definition.signal.arn
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
    security_groups  = [aws_security_group.signal.id]
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.signal_http.arn
    container_name   = local.signal_container_name
    container_port   = local.application_port
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.signal_grpc.arn
    container_name   = local.signal_container_name
    container_port   = local.signal_grpc_port
  }

  tags = local.common_tags

  depends_on = [
    aws_iam_role_policy_attachment.task_execution,
    aws_lb_listener_rule.signal_grpc,
    aws_lb_listener_rule.signal_http,
  ]
}

resource "aws_ecs_service" "dashboard" {
  name             = "${var.name}-dashboard"
  cluster          = aws_ecs_cluster.this.arn
  task_definition  = aws_ecs_task_definition.dashboard.arn
  desired_count    = var.service_resources.dashboard.desired_count
  launch_type      = "FARGATE"
  platform_version = "1.4.0"

  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200
  health_check_grace_period_seconds  = 30
  propagate_tags                     = "SERVICE"

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  network_configuration {
    assign_public_ip = false
    subnets          = var.private_subnet_ids
    security_groups  = [aws_security_group.dashboard.id]
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.dashboard.arn
    container_name   = local.dashboard_container_name
    container_port   = local.application_port
  }

  tags = local.common_tags

  depends_on = [
    aws_iam_role_policy_attachment.task_execution,
    aws_lb_listener_rule.dashboard,
  ]
}
