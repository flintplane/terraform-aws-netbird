locals {
  aws_region           = split(":", var.certificate_arn)[3]
  relay_container_name = "relay"
  relay_container_port = 33080
  stun_container_port  = 3478

  relay_auth_secret_current_version_id = one([
    for version in data.aws_secretsmanager_secret_versions.relay_auth.versions : version.version_id
    if contains(version.version_stages, "AWSCURRENT")
  ])

  valid_fargate_size = (
    var.cpu == 256 ? contains([512, 1024, 2048], var.memory) :
    var.cpu == 512 ? var.memory >= 1024 && var.memory <= 4096 && var.memory % 1024 == 0 :
    var.cpu == 1024 ? var.memory >= 2048 && var.memory <= 8192 && var.memory % 1024 == 0 :
    var.cpu == 2048 ? var.memory >= 4096 && var.memory <= 16384 && var.memory % 1024 == 0 :
    var.cpu == 4096 ? var.memory >= 8192 && var.memory <= 30720 && var.memory % 1024 == 0 :
    var.cpu == 8192 ? var.memory >= 16384 && var.memory <= 61440 && var.memory % 4096 == 0 :
    var.cpu == 16384 ? var.memory >= 32768 && var.memory <= 122880 && var.memory % 8192 == 0 :
    false
  )

  relay_uri = "rels://${var.fqdn}:443"
  stun_uri  = "stun:${var.fqdn}:3478"

  common_tags = merge(var.tags, {
    Name      = var.name
    Component = "netbird-relay"
  })
}
