module "netbird_relay" {
  source = "../../modules/relay"

  name               = "netbird-relay-1"
  vpc_id             = "vpc-0123456789abcdef0"
  public_subnet_ids  = ["subnet-0123456789abcdef0", "subnet-11111111111111111"]
  private_subnet_ids = ["subnet-22222222222222222", "subnet-33333333333333333"]

  fqdn                  = "relay1.netbird.example.com"
  route53_zone_id       = "Z0123456789ABCDEFGHIJ"
  certificate_arn       = "arn:aws:acm:eu-central-1:123456789012:certificate/00000000-0000-0000-0000-000000000000"
  relay_auth_secret_arn = "arn:aws:secretsmanager:eu-central-1:123456789012:secret:netbird-relay-AbCdEf"
  image                 = "netbirdio/relay:0.79.0"

  tags = {
    Environment = "production"
    Service     = "netbird"
  }
}

output "relay_uri" {
  value = module.netbird_relay.relay_uri
}

output "stun_uri" {
  value = module.netbird_relay.stun_uri
}
