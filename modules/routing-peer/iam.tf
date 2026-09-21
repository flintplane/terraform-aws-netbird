data "aws_iam_policy_document" "ecs_infrastructure_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ecs_infrastructure" {
  name_prefix        = "${var.name}-infrastructure-"
  assume_role_policy = data.aws_iam_policy_document.ecs_infrastructure_assume_role.json
  tags               = local.common_tags
}

resource "aws_iam_role_policy_attachment" "ecs_infrastructure" {
  role       = aws_iam_role.ecs_infrastructure.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonECSInfrastructureRolePolicyForManagedInstances"
}

data "aws_iam_policy_document" "managed_storage_kms" {
  statement {
    sid       = "DescribeManagedStorageKey"
    actions   = ["kms:DescribeKey"]
    resources = [aws_kms_key.managed_storage.arn]
  }

  statement {
    sid = "GenerateManagedStorageDataKey"
    actions = [
      "kms:GenerateDataKey",
      "kms:GenerateDataKeyWithoutPlaintext",
    ]
    resources = [aws_kms_key.managed_storage.arn]

    condition {
      test     = "StringEquals"
      variable = "kms:CallerAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }

    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["ec2.${data.aws_region.current.region}.amazonaws.com"]
    }

    condition {
      test     = "ForAnyValue:StringEquals"
      variable = "kms:EncryptionContextKeys"
      values   = ["aws:ebs:id"]
    }
  }

  statement {
    sid       = "CreateManagedStorageGrant"
    actions   = ["kms:CreateGrant"]
    resources = [aws_kms_key.managed_storage.arn]

    condition {
      test     = "StringEquals"
      variable = "kms:CallerAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }

    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["ec2.${data.aws_region.current.region}.amazonaws.com"]
    }

    condition {
      test     = "ForAnyValue:StringEquals"
      variable = "kms:EncryptionContextKeys"
      values   = ["aws:ebs:id"]
    }

    condition {
      test     = "Bool"
      variable = "kms:GrantIsForAWSResource"
      values   = ["true"]
    }
  }
}

resource "aws_iam_role_policy" "managed_storage_kms" {
  name_prefix = "managed-storage-kms-"
  role        = aws_iam_role.ecs_infrastructure.id
  policy      = data.aws_iam_policy_document.managed_storage_kms.json
}

data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ecs_instance" {
  name               = "ecsInstanceRole-${var.name}"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json
  tags               = local.common_tags
}

resource "aws_iam_role_policy_attachment" "ecs_instance" {
  role       = aws_iam_role.ecs_instance.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonECSInstanceRolePolicyForManagedInstances"
}

resource "aws_iam_instance_profile" "ecs_instance" {
  name = "ecsInstanceRole-${var.name}"
  role = aws_iam_role.ecs_instance.name
  tags = local.common_tags
}

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
  name_prefix        = "${var.name}-execution-"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_assume_role.json
  tags               = local.common_tags
}

resource "aws_iam_role_policy_attachment" "task_execution" {
  role       = aws_iam_role.task_execution.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

data "aws_iam_policy_document" "setup_key_secret" {
  statement {
    sid       = "ReadNetBirdSetupKey"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [var.setup_key_secret_arn]
  }
}

resource "aws_iam_role_policy" "setup_key_secret" {
  name_prefix = "setup-key-secret-"
  role        = aws_iam_role.task_execution.id
  policy      = data.aws_iam_policy_document.setup_key_secret.json
}
