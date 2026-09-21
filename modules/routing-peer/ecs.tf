resource "aws_cloudwatch_log_group" "this" {
  name              = "/aws/ecs/${var.name}"
  retention_in_days = var.log_retention_days
  tags              = local.common_tags
}

resource "aws_ecs_cluster" "this" {
  name = var.name

  configuration {
    managed_storage_configuration {
      kms_key_id = aws_kms_key.managed_storage.arn
    }
  }

  setting {
    name  = "containerInsights"
    value = "enhanced"
  }

  tags = local.common_tags
}

resource "aws_ecs_capacity_provider" "this" {
  name    = var.name
  cluster = aws_ecs_cluster.this.name

  managed_instances_provider {
    infrastructure_role_arn = aws_iam_role.ecs_infrastructure.arn
    propagate_tags          = "CAPACITY_PROVIDER"

    instance_launch_template {
      capacity_option_type     = "ON_DEMAND"
      ec2_instance_profile_arn = aws_iam_instance_profile.ecs_instance.arn
      monitoring               = "DETAILED"

      network_configuration {
        subnets         = sort(tolist(var.subnet_ids))
        security_groups = [aws_security_group.instance.id]
      }

      storage_configuration {
        storage_size_gib = 30
      }
    }
  }

  tags = local.common_tags

  depends_on = [
    aws_iam_role_policy_attachment.ecs_infrastructure,
    aws_iam_role_policy.managed_storage_kms,
    aws_iam_role_policy_attachment.ecs_instance,
  ]
}

# ECS accepts a Managed Instances capacity provider before it is usable by a
# service. The AWS provider does not currently wait for its status to become
# ACTIVE, so leave time for the asynchronous activation to finish.
resource "time_sleep" "capacity_provider_activation" {
  create_duration = "30s"

  depends_on = [aws_ecs_capacity_provider.this]

  lifecycle {
    replace_triggered_by = [aws_ecs_capacity_provider.this]
  }
}

resource "aws_ecs_task_definition" "this" {
  family                   = var.name
  requires_compatibilities = ["MANAGED_INSTANCES"]
  network_mode             = "awsvpc"
  cpu                      = tostring(local.task_cpu)
  memory                   = tostring(local.task_memory)
  execution_role_arn       = aws_iam_role.task_execution.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  container_definitions = jsonencode([
    {
      name      = local.container_name
      image     = var.image
      essential = true
      cpu       = local.task_cpu
      memory    = local.task_memory

      environment = [
        {
          name  = "NB_LOG_LEVEL"
          value = "info"
        },
        {
          name  = "NB_MANAGEMENT_URL"
          value = var.management_url
        },
      ]

      secrets = [
        {
          name      = "NB_SETUP_KEY"
          valueFrom = "${var.setup_key_secret_arn}:::${local.setup_key_secret_current_version_id}"
        },
      ]

      linuxParameters = {
        initProcessEnabled = true
        capabilities = {
          add  = ["NET_ADMIN", "SYS_ADMIN", "SYS_RESOURCE"]
          drop = []
        }
        devices = [
          {
            hostPath      = "/dev/net/tun"
            containerPath = "/dev/net/tun"
            permissions   = ["read", "write"]
          },
        ]
      }

      systemControls = [
        {
          namespace = "net.ipv4.ip_forward"
          value     = "1"
        },
        {
          namespace = "net.ipv4.conf.all.src_valid_mark"
          value     = "1"
        },
      ]

      healthCheck = {
        command     = ["CMD-SHELL", "netbird status --check live || exit 1"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 60
      }

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.this.name
          awslogs-region        = data.aws_region.current.region
          awslogs-stream-prefix = "routing-peer"
        }
      }

      stopTimeout = 120
    },
  ])

  tags = local.common_tags

  lifecycle {
    precondition {
      condition     = split(":", var.setup_key_secret_arn)[3] == data.aws_region.current.region
      error_message = "The setup-key secret must be in the same AWS region as the routing-peer module."
    }
  }
}

resource "aws_ecs_service" "this" {
  name            = var.name
  cluster         = aws_ecs_cluster.this.arn
  task_definition = aws_ecs_task_definition.this.arn
  desired_count   = var.desired_count

  availability_zone_rebalancing      = "ENABLED"
  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200
  enable_ecs_managed_tags            = true
  enable_execute_command             = false
  propagate_tags                     = "SERVICE"

  capacity_provider_strategy {
    capacity_provider = aws_ecs_capacity_provider.this.name
    base              = 0
    weight            = 100
  }

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  network_configuration {
    assign_public_ip = false
    subnets          = sort(tolist(var.subnet_ids))
    security_groups  = [aws_security_group.task.id]
  }

  placement_constraints {
    type = "distinctInstance"
  }

  tags = local.common_tags

  depends_on = [
    aws_iam_role_policy_attachment.task_execution,
    aws_iam_role_policy.setup_key_secret,
    time_sleep.capacity_provider_activation,
  ]
}
