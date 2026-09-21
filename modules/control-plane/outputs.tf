output "dashboard_url" {
  description = "Public URL of the NetBird Dashboard."
  value       = local.dashboard_url
}

output "management_endpoint" {
  description = "Compatibility alias for management_url."
  value       = local.management_url
}

output "signal_endpoint" {
  description = "Compatibility alias for signal_address."
  value       = "${var.endpoints.signal_fqdn}:443"
}

output "management_url" {
  description = "Public HTTPS URL used by the Dashboard and NetBird clients."
  value       = local.management_url
}

output "signal_url" {
  description = "Public HTTPS URL of the Signal service."
  value       = "https://${var.endpoints.signal_fqdn}"
}

output "signal_address" {
  description = "Public host and port advertised by Management for the Signal service."
  value       = "${var.endpoints.signal_fqdn}:443"
}

output "cluster_arn" {
  description = "ARN of the dedicated ECS cluster."
  value       = aws_ecs_cluster.this.arn
}

output "load_balancer_arn" {
  description = "ARN of the public Application Load Balancer."
  value       = aws_lb.this.arn
}

output "service_arns" {
  description = "ARNs of the independent ECS services."
  value = {
    management = aws_ecs_service.management.id
    signal     = aws_ecs_service.signal.id
    dashboard  = aws_ecs_service.dashboard.id
  }
}

output "database_identifier" {
  description = "Identifier of the module-owned PostgreSQL RDS instance."
  value       = aws_db_instance.this.identifier
}

output "database_secret_arn" {
  description = "ARN of the Secrets Manager secret containing the database password."
  value       = aws_secretsmanager_secret.database.arn
}

output "datastore_encryption_key_secret_arn" {
  description = "ARN of the nonrotating Secrets Manager secret containing the NetBird datastore encryption key."
  value       = aws_secretsmanager_secret.datastore_encryption_key.arn
}

output "rds_storage_kms_key_arn" {
  description = "ARN of the dedicated KMS key used only for RDS storage."
  value       = aws_kms_key.rds_storage.arn
}

output "secrets_kms_key_arn" {
  description = "ARN of the KMS key used for module-owned Secrets Manager secrets."
  value       = aws_kms_key.secrets.arn
}
