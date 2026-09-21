data "aws_partition" "current" {}
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
data "aws_secretsmanager_secret_versions" "setup_key" {
  secret_id = var.setup_key_secret_arn
}

locals {
  container_name = "routing-peer"

  task_cpu    = 256
  task_memory = 512

  setup_key_secret_current_version_id = one([
    for version in data.aws_secretsmanager_secret_versions.setup_key.versions : version.version_id
    if contains(version.version_stages, "AWSCURRENT")
  ])

  common_tags = merge(var.tags, {
    Name      = var.name
    Component = "netbird-routing-peer"
  })
}
