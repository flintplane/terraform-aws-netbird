locals {
  aws_region = split(":", var.certificate_arn)[3]

  management_container_name = "management"
  signal_container_name     = "signal"
  dashboard_container_name  = "dashboard"
  application_port          = 80
  signal_grpc_port          = 10000
  database_port             = 5432
  database_name             = "netbird"
  database_username         = "netbird"

  relay_auth_secret_current_version_id = one([
    for version in data.aws_secretsmanager_secret_versions.relay_auth.versions : version.version_id
    if contains(version.version_stages, "AWSCURRENT")
  ])

  service_sizes = {
    management = var.service_resources.management
    signal     = var.service_resources.signal
    dashboard  = var.service_resources.dashboard
  }

  valid_fargate_sizes = {
    for name, size in local.service_sizes : name => (
      size.cpu == 256 ? contains([512, 1024, 2048], size.memory) :
      size.cpu == 512 ? size.memory >= 1024 && size.memory <= 4096 && size.memory % 1024 == 0 :
      size.cpu == 1024 ? size.memory >= 2048 && size.memory <= 8192 && size.memory % 1024 == 0 :
      size.cpu == 2048 ? size.memory >= 4096 && size.memory <= 16384 && size.memory % 1024 == 0 :
      size.cpu == 4096 ? size.memory >= 8192 && size.memory <= 30720 && size.memory % 1024 == 0 :
      size.cpu == 8192 ? size.memory >= 16384 && size.memory <= 61440 && size.memory % 4096 == 0 :
      size.cpu == 16384 ? size.memory >= 32768 && size.memory <= 122880 && size.memory % 8192 == 0 :
      false
    )
  }

  management_url = "https://${var.endpoints.management_fqdn}"
  dashboard_url  = "https://${var.endpoints.dashboard_fqdn}"
  auth_issuer    = "${local.management_url}/oauth2"

  load_balancer_proxy_cidrs = sort([
    for subnet in data.aws_subnet.load_balancer : subnet.cidr_block
  ])

  # NetBird renders management.json with Go text/template before decoding it.
  # Secret placeholders must therefore use {{.NAME}}, not shell ${NAME} syntax.
  management_config = {
    Stuns = [
      for uri in sort(tolist(var.relay.stun_uris)) : {
        Proto    = "udp"
        URI      = uri
        Username = ""
        Password = null
      }
    ]
    TURNConfig = {
      Turns                = []
      CredentialsTTL       = "12h"
      Secret               = ""
      TimeBasedCredentials = false
    }
    Relay = {
      Addresses      = sort(tolist(var.relay.addresses))
      CredentialsTTL = "24h"
      Secret         = "{{.NETBIRD_RELAY_AUTH_SECRET}}"
    }
    Signal = {
      Proto    = "https"
      URI      = "${var.endpoints.signal_fqdn}:443"
      Username = ""
      Password = null
    }
    ReverseProxy = {
      TrustedHTTPProxies      = local.load_balancer_proxy_cidrs
      TrustedHTTPProxiesCount = 1
      TrustedPeers            = local.load_balancer_proxy_cidrs
    }
    DisableDefaultPolicy   = false
    Datadir                = "/var/lib/netbird"
    DataStoreEncryptionKey = "{{.NETBIRD_DATASTORE_ENC_KEY}}"
    StoreConfig = {
      Engine = "postgres"
    }
    EmbeddedIdP = {
      Enabled                         = true
      Issuer                          = local.auth_issuer
      LocalAuthDisabled               = var.local_auth_disabled
      SignKeyRefreshEnabled           = true
      DashboardRedirectURIs           = ["${local.dashboard_url}/nb-auth", "${local.dashboard_url}/nb-silent-auth"]
      DashboardPostLogoutRedirectURIs = [local.dashboard_url]
      CLIRedirectURIs                 = ["http://localhost:53000/"]
      Storage = {
        Type = "postgres"
        Config = {
          DSN = "{{.NETBIRD_AUTH_POSTGRES_DSN}}"
        }
      }
    }
  }

  common_tags = merge(var.tags, {
    Name      = var.name
    Component = "netbird-control-plane"
  })
}
