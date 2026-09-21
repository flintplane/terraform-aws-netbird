module "netbird_control_plane" {
  source = "../../modules/control-plane"

  name               = "netbird-control"
  vpc_id             = "vpc-0123456789abcdef0"
  public_subnet_ids  = ["subnet-0123456789abcdef0", "subnet-11111111111111111"]
  private_subnet_ids = ["subnet-22222222222222222", "subnet-33333333333333333"]
  enable_ipv6        = true

  endpoints = {
    management_fqdn = "management.netbird.example.com"
    signal_fqdn     = "signal.netbird.example.com"
    dashboard_fqdn  = "dashboard.netbird.example.com"
  }

  route53_zone_id = "Z0123456789ABCDEFGHIJ"
  certificate_arn = "arn:aws:acm:eu-central-1:123456789012:certificate/00000000-0000-0000-0000-000000000000"

  images = {
    management = "netbirdio/management:0.79.0"
    signal     = "netbirdio/signal:0.79.0"
    dashboard  = "netbirdio/dashboard:v2.90.8"
  }

  relay = {
    auth_secret_arn = "arn:aws:secretsmanager:eu-central-1:123456789012:secret:netbird-relay-AbCdEf"
    addresses       = ["rels://relay1.netbird.example.com:443"]
    stun_uris       = ["stun:relay1.netbird.example.com:3478"]
  }

  netbird_dns_domain         = "nb.internal.example.com"
  single_account_mode_domain = "example.com"
  local_auth_disabled        = false

  database = {
    engine_version        = "16"
    instance_class        = "db.t4g.small"
    allocated_storage_gib = 20
    max_storage_gib       = 100
    backup_retention_days = 14
    multi_az              = true
    deletion_protection   = true
    password_version      = 1
  }

  service_resources = {
    management = {
      cpu    = 512
      memory = 1024
    }
    signal = {
      cpu    = 256
      memory = 512
    }
    dashboard = {
      cpu           = 256
      memory        = 512
      desired_count = 1
    }
  }

  tags = {
    Environment = "production"
    Service     = "netbird"
  }
}
