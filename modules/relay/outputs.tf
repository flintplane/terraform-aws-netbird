output "relay_uri" {
  description = "TLS Relay URI to configure in the NetBird Management service."
  value       = local.relay_uri
}

output "stun_uri" {
  description = "STUN URI to configure in the NetBird Management service."
  value       = local.stun_uri
}

output "service_arn" {
  description = "ARN of the ECS Relay service."
  value       = aws_ecs_service.this.id
}

output "load_balancer_arn" {
  description = "ARN of the public Network Load Balancer."
  value       = aws_lb.this.arn
}
