data "aws_partition" "current" {}
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

data "aws_iam_policy_document" "ecs_task_assume_role" {
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

resource "aws_iam_role" "task_execution" {
  for_each = toset(["management", "signal", "dashboard"])

  name_prefix        = "${var.name}-${each.key}-exec-"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_assume_role.json
  tags               = local.common_tags
}

resource "aws_iam_role_policy_attachment" "task_execution" {
  for_each = aws_iam_role.task_execution

  role       = each.value.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

data "aws_iam_policy_document" "management_secrets" {
  statement {
    sid     = "ReadRuntimeSecrets"
    actions = ["secretsmanager:GetSecretValue"]
    resources = [
      var.relay.auth_secret_arn,
      aws_secretsmanager_secret.datastore_encryption_key.arn,
      aws_secretsmanager_secret.session_cookie_encryption_key.arn,
      aws_secretsmanager_secret.database.arn,
    ]
  }

  statement {
    sid       = "DecryptModuleSecrets"
    actions   = ["kms:Decrypt"]
    resources = [aws_kms_key.secrets.arn]
  }
}

resource "aws_iam_role_policy" "management_secrets" {
  name_prefix = "management-secrets-"
  role        = aws_iam_role.task_execution["management"].id
  policy      = data.aws_iam_policy_document.management_secrets.json
}
