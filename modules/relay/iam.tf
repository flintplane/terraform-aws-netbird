data "aws_iam_policy_document" "task_execution_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:${data.aws_partition.current.partition}:ecs:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:*"]
    }
  }
}

data "aws_partition" "current" {}
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

data "aws_secretsmanager_secret_versions" "relay_auth" {
  secret_id = var.relay_auth_secret_arn
}

resource "aws_iam_role" "task_execution" {
  name_prefix        = "${var.name}-execution-"
  assume_role_policy = data.aws_iam_policy_document.task_execution_assume_role.json
  tags               = local.common_tags
}

resource "aws_iam_role_policy_attachment" "task_execution" {
  role       = aws_iam_role.task_execution.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

data "aws_iam_policy_document" "relay_secret" {
  statement {
    sid       = "ReadRelayAuthenticationSecret"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [var.relay_auth_secret_arn]
  }
}

resource "aws_iam_role_policy" "relay_secret" {
  name_prefix = "relay-secret-"
  role        = aws_iam_role.task_execution.id
  policy      = data.aws_iam_policy_document.relay_secret.json
}
