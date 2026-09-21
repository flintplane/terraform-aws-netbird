resource "aws_kms_key" "managed_storage" {
  description             = "ECS managed storage for ${var.name} NetBird routing peers"
  deletion_window_in_days = 30
  enable_key_rotation     = true
  tags                    = local.common_tags
}

resource "aws_kms_alias" "managed_storage" {
  name          = "alias/${var.name}-ecs-managed-storage"
  target_key_id = aws_kms_key.managed_storage.key_id
}
