# NetBird control-plane module

Deploys the standalone NetBird Management, Signal, and Dashboard images as separate ECS Fargate services. The services share a public Application Load Balancer and a dedicated ECS cluster, but each has its own task definition, ECS service, security group, IAM roles, target groups, and log group.

The module also creates a private, provisioned PostgreSQL RDS instance for Management and enables NetBird's embedded identity provider inside the Management process. It does not create a VPC, subnets, Route53 zone, ACM certificate, Relay, or external identity-provider resources.

## Owned resources

- Dedicated ECS cluster
- Separate Management, Signal, and Dashboard Fargate services
- Internet-facing Application Load Balancer and HTTPS listener
- Separate HTTP/1.1 and gRPC target groups where required
- Route53 `A` alias records for all three public endpoints and optional `AAAA` aliases
- Security groups and per-service task-execution IAM roles
- Separate CloudWatch log groups
- Single-AZ PostgreSQL RDS instance by default
- Dedicated customer-managed KMS key and alias for RDS storage
- Separate customer-managed KMS key and alias for module-owned secrets
- Generated database password, NetBird datastore encryption key, and embedded IdP session-cookie encryption key
- Three Secrets Manager secrets containing those generated values

Database defaults are deliberately conservative for a low-cost initial deployment: Single-AZ, seven days of backups, and deletion protection disabled. The production example below explicitly enables Multi-AZ and deletion protection and retains 14 days of backups. Choose these values from the environment's recovery objectives rather than relying silently on module defaults.

## Runtime boundaries

Management, Signal, and Dashboard are independently replaceable ECS services. Management and Signal each run as a singleton with stop-then-start deployments. This avoids briefly running two copies while their horizontal-scaling behavior remains unverified. Dashboard uses a normal rolling deployment and its replica count is configurable.

TLS terminates at the ALB. It routes gRPC to h2c target groups and API or WebSocket traffic to HTTP/1.1 target groups. Management is the only task allowed to connect to PostgreSQL. The main Management store, activity/audit store, and embedded IdP store use the same RDS database; NetBird keeps their tables separate.

Management trusts forwarded client addresses only from the ALB. The module derives the trusted proxy networks from the IPv4 CIDRs of `public_subnet_ids` and configures one trusted HTTP proxy hop. This preserves the originating client address without accepting forwarded-address headers from arbitrary sources.

The ALB idle timeout is 4,000 seconds, the AWS maximum. NetBird keeps Management and Signal gRPC streams open for long periods, and ALB HTTP/2 PING frames do not reset the idle timer. A long timeout reduces unnecessary control-plane reconnections during quiet periods; it does not affect established peer-to-peer or relayed WireGuard data paths.

The Fargate tasks do not receive public IP addresses. Private subnets must provide NAT or the VPC endpoints needed for image pulls, CloudWatch Logs, Secrets Manager, and KMS. Management also needs outbound HTTPS access to the configured external identity provider.

When `enable_ipv6` is true, only the public ALB frontend becomes dual-stack. The ALB publishes IPv4 and IPv6 addresses while continuing to forward to IPv4 target groups. The Fargate tasks, RDS instance, and private application paths do not require IPv6.

Terraform does not wait for ECS services to reach steady state. After apply, confirm the three running task counts, five target-group health states, ECS service events, and application logs. `wait_for_steady_state` may be enabled in a later milestone once its failure and deployment-time behavior has been evaluated operationally.

## Requirements

This module requires Terraform 1.11 or newer. It uses ephemeral resources and write-only arguments so generated secrets are not persisted in Terraform plan or state files.

### Optional IPv6 frontend

Set `enable_ipv6 = true` to make Management, Signal, and Dashboard reachable over both IPv4 and IPv6. Every supplied public subnet must have an IPv6 `/64` and `::/0` routed to an internet gateway. Network ACLs must permit inbound HTTPS and return traffic over IPv6. The ALB does not require automatic IPv6 assignment for arbitrary new subnet ENIs.

The module configures a dual-stack ALB, permits IPv6 TCP/443 at its security group, and creates `AAAA` aliases alongside the existing `A` aliases. It does not change backend target groups from IPv4 and does not require the ECS `dualStackIPv6` account setting for this frontend-only feature.

See the repository [IPv6 guide](../../IPV6.md) for the scope, shared-infrastructure responsibilities, checks, and rollback procedure. Relay remains IPv4-only in this milestone.

## Secrets and state

The module generates three long-lived values:

- A 32-byte, base64-encoded NetBird datastore encryption key
- A separate 32-byte, base64-encoded embedded IdP session-cookie encryption key
- A PostgreSQL password stored as a raw secret value

Terraform generates these values ephemerally and writes them to Secrets Manager through write-only arguments. Terraform state records secret metadata, such as ARNs and version IDs, but does not contain any plaintext value. The values exist transiently in the Terraform and provider processes and are sent to the relevant AWS APIs during apply.

The datastore key is required for stable Management recovery. Losing or changing it makes previously encrypted datastore fields unreadable. It has no rotation control because changing it requires a coordinated NetBird data migration. The session-cookie key is also stable across Management task replacements; changing it invalidates active embedded IdP sessions.

The database password is not rotated automatically. `database.password_version` defaults to `1`. To rotate it, increment that value by one and apply. Terraform creates a new password, stores it as a new Secrets Manager version, updates RDS with that exact stored value, registers a new Management task definition that references the new secret version, and replaces the Management task. Keep the incremented number in configuration; use the next integer for the next rotation.

Do not remove the secret-version resources from Terraform state. Terraform would lose the metadata that prevents routine applies from generating replacement values.

The module creates two customer-managed KMS keys with annual automatic rotation. One is dedicated to RDS storage, so RDS does not use the AWS-managed `aws/rds` key. The other encrypts the three module-owned Secrets Manager secrets.

The Relay authentication secret is the only value that must exist before this module is applied. It must be in the same AWS region as the control plane and contain its complete plaintext value rather than JSON. It is a long-lived secret without automatic rotation. When it is replaced in Secrets Manager, run plan and apply: the module detects the new `AWSCURRENT` version ID and replaces the Management task so ECS injects the new value.

The Terraform caller needs `secretsmanager:ListSecretVersionIds` for the Relay secret. Terraform reads version metadata to detect `AWSCURRENT`; it does not read the external secret value.

This version expects the external secrets to use the default `aws/secretsmanager` KMS key. Supporting external secrets encrypted with customer-managed KMS keys requires execution-role decrypt permissions and a future public-interface change.

## Authentication model

The embedded identity provider runs inside the Management task and publishes its OIDC issuer at `https://<management-fqdn>/oauth2`. Dashboard and NetBird clients authenticate against that issuer. External providers are configured through the NetBird Dashboard and their connector data is stored in the embedded IdP PostgreSQL tables.

`local_auth_disabled` defaults to `false`. Keep it false for first-run setup and until the selected external provider, Owner identity, client login, and recovery procedure have been tested. A deployment can then disable local authentication or retain it for governed break-glass use. Management intentionally refuses to start with local authentication disabled when no external provider exists. Re-enable the setting and redeploy Management when local break-glass login is required in a deployment where it is normally disabled.

### External identity-provider bootstrap

The provider connector is NetBird application data and is intentionally not part of this Terraform module. The general sequence is:

1. Deploy with `local_auth_disabled = false` and create the first local Owner through the Dashboard setup page.
2. Create an OIDC application in the external provider using NetBird's displayed callback and logout URLs.
3. Restrict application assignment according to the organization's identity policy.
4. Add the provider in NetBird and keep the local Owner session open.
5. Test a new external-provider login, user admission, roles, claims, logout, and client enrollment.
6. Establish the intended Owner-continuity and break-glass procedures.
7. If local login should be disabled, set `local_auth_disabled = true`, apply, and repeat the authentication and client tests.

Group synchronization does not grant the NetBird Owner or Admin role; manage privileged roles explicitly in NetBird. Connector credentials are logical NetBird data stored in PostgreSQL and are not Terraform or Secrets Manager inputs.

See [OKTA.md](./OKTA.md) for a provider-specific example covering current Okta and NetBird UI fields, exact callbacks, testing, group claims, ownership, local-auth cutover, and lifecycle guidance.

## Usage

```hcl
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

  netbird_dns_domain          = "nb.internal.example.com"
  single_account_mode_domain = "example.com"
  local_auth_disabled         = false

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
```

Use immutable image digests for production deployments. Management and Signal should use images from the same NetBird release.

## Initial checks

After deployment:

1. Confirm all five target groups are healthy.
2. Check the Management, Signal, and Dashboard log groups for startup errors.
3. Open the Dashboard URL and complete the first-run local Owner setup.
4. Configure the selected external identity provider, complete its user-admission and role process, and verify a new login.
5. Enroll a test peer against the Management endpoint and verify authentication through the external provider.
6. Confirm the peer reports connected Management, Signal, and Relay endpoints.
7. If local authentication is disabled, apply that setting and verify that only the external-provider login is offered.
8. Stop one task at a time and verify ECS replaces it.

When IPv6 is enabled, query both the `A` and `AAAA` records for all three endpoints and test the Management health endpoint over `curl -4` and `curl -6`. DNS and HTTPS checks supplement rather than replace the gRPC, WebSocket, login, and client-enrollment checks above.

The ALB checks Management's public instance endpoint. Signal has no dedicated HTTP/1.1 health endpoint, so its WebSocket target group probes the neutral root path and treats the expected client-error response as healthy. Probing `/ws-proxy/signal` would attempt an invalid WebSocket handshake and return a server error. Signal WebSocket traffic uses port 80, while native gRPC traffic and its protocol-aware health check use Signal's dedicated port 10000. Management's gRPC check calls its `isHealthy` RPC; Signal expects the standard unimplemented response on the ALB probe path.

## Recovery and deletion

RDS retains seven days of automated backups by default. Module deletion creates a final snapshot named `<name>-final-<random-suffix>`. The suffix is generated once and remains stable in Terraform state. A date derived from `timestamp()` would change every plan, so it is unsuitable for a declarative final-snapshot identifier. The random suffix avoids collisions between complete destroy-and-recreate cycles; snapshots still need an external retention and naming policy.

Enable `database.deletion_protection` for production deployments. To intentionally destroy a protected database, first change that setting to `false`, review and apply that change, and then perform the separately reviewed destroy operation.

Both KMS keys have 30-day deletion windows. Keep the RDS storage key as long as any database snapshot encrypted by it must remain recoverable. Keep the secrets KMS key, datastore-key secret, and session-cookie-key secret with the corresponding database backups.

## Inputs

| Name | Type | Required | Description |
| --- | --- | --- | --- |
| `name` | `string` | yes | Short resource name for this control plane. |
| `vpc_id` | `string` | yes | Existing VPC ID. |
| `public_subnet_ids` | `set(string)` | yes | At least two subnets for the public ALB. |
| `private_subnet_ids` | `set(string)` | yes | At least two subnets for tasks and RDS. |
| `enable_ipv6` | `bool` | no, `false` | Publish the public ALB endpoints over both IPv4 and IPv6; backend targets remain IPv4. |
| `endpoints` | `object` | yes | Distinct Management, Signal, and Dashboard FQDNs. |
| `route53_zone_id` | `string` | yes | Existing hosted-zone ID. |
| `certificate_arn` | `string` | yes | Existing ACM certificate covering all endpoints. |
| `images` | `object` | yes | Pinned Management, Signal, and Dashboard images. |
| `relay` | `object` | yes | Relay secret ARN and advertised Relay/STUN URIs. |
| `netbird_dns_domain` | `string` | yes | Private peer-name suffix, such as `nb.internal.example.com`. |
| `single_account_mode_domain` | `string` | yes | Identity domain whose users join the same NetBird account. |
| `local_auth_disabled` | `bool` | no, `false` | Disable local login after external authentication is verified. |
| `database` | `object` | no, `{}` | RDS version, size, storage, backups, HA, protection, and password revision. |
| `service_resources` | `object` | no, `{}` | Fargate sizing and Dashboard replica count. |
| `log_retention_days` | `number` | no, `30` | CloudWatch Logs retention. |
| `tags` | `map(string)` | no, `{}` | Additional resource tags. |

## Outputs

| Name | Description |
| --- | --- |
| `dashboard_url` | Public Dashboard HTTPS URL. |
| `management_url` | Public Management HTTPS URL. |
| `signal_url` | Public Signal HTTPS URL. |
| `signal_address` | Signal `host:port` advertised by Management. |
| `management_endpoint` | Compatibility alias for `management_url`. |
| `signal_endpoint` | Compatibility alias for `signal_address`. |
| `cluster_arn` | Dedicated ECS cluster ARN. |
| `load_balancer_arn` | ALB ARN. |
| `service_arns` | Management, Signal, and Dashboard ECS service ARNs. |
| `database_identifier` | RDS instance identifier. |
| `database_secret_arn` | Database-password secret ARN. |
| `datastore_encryption_key_secret_arn` | NetBird datastore-key secret ARN. |
| `rds_storage_kms_key_arn` | RDS storage KMS key ARN. |
| `secrets_kms_key_arn` | Module-secret KMS key ARN. |
