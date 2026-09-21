resource "aws_security_group" "instance" {
  name_prefix = "${var.name}-instance-"
  description = "Bottlerocket hosts for the ${var.name} NetBird routing peers"
  vpc_id      = var.vpc_id

  egress {
    description = "ECS host runtime dependencies"
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
  description = "Task ENIs for the ${var.name} NetBird routing peers"
  vpc_id      = var.vpc_id

  egress {
    description      = "NetBird control plane, peers, and routed destinations"
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = var.enable_ipv6 ? ["::/0"] : []
  }

  tags = local.common_tags

  lifecycle {
    create_before_destroy = true
  }
}
