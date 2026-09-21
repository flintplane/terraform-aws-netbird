module "central_routing_peer" {
  source = "../../modules/routing-peer"

  name   = "netbird-router"
  vpc_id = "vpc-0123456789abcdef0"
  subnet_ids = [
    "subnet-0123456789abcdef0",
    "subnet-0fedcba9876543210",
  ]
  enable_ipv6 = true

  image                = "netbirdio/netbird:0.79.0"
  management_url       = "https://management.netbird.example.com"
  setup_key_secret_arn = "arn:aws:secretsmanager:eu-central-1:123456789012:secret:netbird/routing-peer-AbCdEf"

  desired_count      = 2
  log_retention_days = 90

  tags = {
    Environment = "production"
    Service     = "netbird"
  }
}
