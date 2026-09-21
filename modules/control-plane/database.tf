resource "aws_kms_key" "rds_storage" {
  description             = "NetBird ${var.name} RDS storage"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  tags                    = local.common_tags
}

resource "aws_kms_alias" "rds_storage" {
  name          = "alias/${var.name}-rds"
  target_key_id = aws_kms_key.rds_storage.key_id
}

resource "aws_kms_key" "secrets" {
  description             = "NetBird ${var.name} module-owned Secrets Manager values"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  tags                    = local.common_tags
}

resource "aws_kms_alias" "secrets" {
  name          = "alias/${var.name}-secrets"
  target_key_id = aws_kms_key.secrets.key_id
}

ephemeral "random_password" "datastore_seed" {
  length  = 64
  special = false
}

ephemeral "random_password" "session_cookie_seed" {
  length  = 64
  special = false
}

ephemeral "random_password" "database" {
  length           = 40
  special          = true
  override_special = "_-+"
}

resource "aws_secretsmanager_secret" "datastore_encryption_key" {
  name_prefix             = "${var.name}/datastore-encryption-key-"
  description             = "NetBird Management datastore encryption key; rotation requires a coordinated data migration"
  kms_key_id              = aws_kms_key.secrets.arn
  recovery_window_in_days = 30
  tags                    = local.common_tags
}

resource "aws_secretsmanager_secret_version" "datastore_encryption_key" {
  secret_id                = aws_secretsmanager_secret.datastore_encryption_key.id
  secret_string_wo         = base64sha256(ephemeral.random_password.datastore_seed.result)
  secret_string_wo_version = 1
}

resource "aws_secretsmanager_secret" "session_cookie_encryption_key" {
  name_prefix             = "${var.name}/session-cookie-encryption-key-"
  description             = "NetBird embedded IdP session-cookie encryption key"
  kms_key_id              = aws_kms_key.secrets.arn
  recovery_window_in_days = 30
  tags                    = local.common_tags
}

resource "aws_secretsmanager_secret_version" "session_cookie_encryption_key" {
  secret_id                = aws_secretsmanager_secret.session_cookie_encryption_key.id
  secret_string_wo         = base64sha256(ephemeral.random_password.session_cookie_seed.result)
  secret_string_wo_version = 1
}

resource "aws_secretsmanager_secret" "database" {
  name_prefix             = "${var.name}/database-"
  description             = "NetBird Management PostgreSQL password; rotated only by an explicit password_version change"
  kms_key_id              = aws_kms_key.secrets.arn
  recovery_window_in_days = 30
  tags                    = local.common_tags
}

resource "aws_secretsmanager_secret_version" "database" {
  secret_id                = aws_secretsmanager_secret.database.id
  secret_string_wo         = ephemeral.random_password.database.result
  secret_string_wo_version = var.database.password_version
}

resource "random_id" "final_snapshot" {
  byte_length = 4
}

ephemeral "aws_secretsmanager_secret_version" "database" {
  secret_id  = aws_secretsmanager_secret.database.id
  version_id = aws_secretsmanager_secret_version.database.version_id
}

resource "aws_db_subnet_group" "this" {
  name_prefix = "${var.name}-"
  description = "Private subnets for the ${var.name} NetBird database"
  subnet_ids  = var.private_subnet_ids
  tags        = local.common_tags
}

resource "aws_db_instance" "this" {
  identifier_prefix = "${var.name}-"

  engine         = "postgres"
  engine_version = var.database.engine_version
  instance_class = var.database.instance_class

  db_name             = local.database_name
  username            = local.database_username
  password_wo         = ephemeral.aws_secretsmanager_secret_version.database.secret_string
  password_wo_version = var.database.password_version
  port                = local.database_port

  allocated_storage     = var.database.allocated_storage_gib
  max_allocated_storage = var.database.max_storage_gib
  storage_type          = "gp3"
  storage_encrypted     = true
  kms_key_id            = aws_kms_key.rds_storage.arn

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.database.id]
  publicly_accessible    = false
  multi_az               = var.database.multi_az

  backup_retention_period = var.database.backup_retention_days
  backup_window           = "02:00-03:00"
  maintenance_window      = "sun:03:00-sun:04:00"
  copy_tags_to_snapshot   = true

  auto_minor_version_upgrade = true
  deletion_protection        = var.database.deletion_protection
  skip_final_snapshot        = false
  final_snapshot_identifier  = "${var.name}-final-${random_id.final_snapshot.hex}"

  tags = local.common_tags
}
