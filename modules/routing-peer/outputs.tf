output "cluster_arn" {
  description = "ARN of the dedicated ECS cluster."
  value       = aws_ecs_cluster.this.arn
}

output "capacity_provider_arn" {
  description = "ARN of the ECS Managed Instances capacity provider."
  value       = aws_ecs_capacity_provider.this.arn
}

output "service_arn" {
  description = "ARN of the ECS routing-peer service."
  value       = aws_ecs_service.this.id
}

output "instance_security_group_id" {
  description = "ID of the security group attached to the Bottlerocket Managed Instances."
  value       = aws_security_group.instance.id
}

output "task_security_group_id" {
  description = "ID of the security group attached to the routing-peer task ENIs."
  value       = aws_security_group.task.id
}

output "log_group_name" {
  description = "Name of the CloudWatch log group containing routing-peer logs."
  value       = aws_cloudwatch_log_group.this.name
}

output "managed_storage_kms_key_arn" {
  description = "ARN of the dedicated KMS key used for ECS managed storage."
  value       = aws_kms_key.managed_storage.arn
}
