# NetBird Relay module

Deploys one independently addressable NetBird Relay and embedded STUN endpoint on ECS Fargate. Each module instance is a singleton relay site with its own public Network Load Balancer and DNS name.

## Owned resources

- ECS task definition and singleton Fargate service
- Dedicated ECS cluster
- Internet-facing Network Load Balancer
- TLS listener on TCP/443 and STUN listener on UDP/3478
- Relay and STUN target groups
- Route53 alias record
- Security groups
- ECS task execution role and secret-read policy
- CloudWatch log group

The module does not create a VPC, subnets, ACM certificate, Route53 zone, or Relay authentication secret.

## Runtime contract

The secret referenced by `relay_auth_secret_arn` must contain the Relay authentication secret as its complete plaintext value. Configure the same value in the NetBird Management service and every Relay site.

The Fargate task runs without a public IP. Its private subnets must provide NAT access or VPC endpoints for the container registry, CloudWatch Logs, Secrets Manager, and any KMS key used by the secret.

TLS terminates at the NLB. Traffic from the NLB to the Relay task uses plain TCP inside the VPC. The target groups use TCP health checks because the Relay application health endpoint can consider its locally configured certificate state, while TLS is external in this deployment.

The module exposes IPv4 only and does not enable Relay QUIC on UDP/443. This does not prevent peers with global IPv6 connectivity from establishing direct IPv6 P2P connections; the IPv4 Relay remains available when direct connectivity fails.

Native IPv6 Relay and STUN support is intentionally deferred. The same NLB currently serves Relay over TCP/443 and STUN over UDP/3478. AWS does not allow an IPv4 target group behind a UDP listener on a dual-stack NLB, so converting this NLB to dual-stack cannot preserve the existing IPv4 STUN target path while adding a same-family IPv6 target path. Cross-family forwarding to an IPv6 target also does not preserve the IPv4 client's address, which STUN needs to report accurately. Supporting both families therefore requires a different frontend design rather than an `enable_ipv6` switch on the current NLB.

QUIC is a separate deferred decision. Adding it requires reviewing UDP/443, TLS termination, certificates, security groups, and target-group behavior together.

Terraform does not wait for the ECS service to reach steady state. After apply, confirm that the task is running, both target groups are healthy, and the Relay startup log advertises the expected URI.

## Create or copy the Relay authentication secret

Generate the authentication value only once for a NetBird control plane. When creating the regional Secrets Manager secret, enter that existing value at the prompt. The input is not echoed:

```bash
printf 'Relay authentication secret: '
read -s NETBIRD_RELAY_AUTH_SECRET
printf '\n'

printf '%s' "$NETBIRD_RELAY_AUTH_SECRET" | aws secretsmanager create-secret \
  --name netbird/relay-auth \
  --secret-string file:///dev/stdin \
  --query ARN \
  --output text

unset NETBIRD_RELAY_AUTH_SECRET
```

Pass the returned ARN to `relay_auth_secret_arn`.

The secret is part of the NetBird protocol configuration:

- Management and every Relay site attached to that Management service must use the same secret value. When deploying another Relay, copy this value; do not generate a new one.
- Do not enable automatic rotation. Rotation requires updating Management and every Relay site together. The module resolves the secret's `AWSCURRENT` version ID, so a subsequent plan registers a new task definition and replaces the Relay task. Apply the same value to every site and Management as one controlled operation.
- The current module supports secrets encrypted with the default `aws/secretsmanager` KMS key. A customer-managed KMS key requires an additional `kms:Decrypt` permission for the task execution role.
- Secrets Manager secrets are regional. For another region, replicate this secret so it retains the same value, then pass the replica ARN to that region's Relay module.
- Store the authentication secret as the complete `SecretString`, not as a JSON field.
- The Terraform caller needs `secretsmanager:ListSecretVersionIds` for this secret. Terraform reads version metadata to detect `AWSCURRENT`; it does not read the secret value.

## Usage

```hcl
module "netbird_relay" {
  source = "../../modules/relay"

  name               = "netbird-relay-ee"
  vpc_id             = "vpc-0123456789abcdef0"
  public_subnet_ids  = ["subnet-0123456789abcdef0", "subnet-11111111111111111"]
  private_subnet_ids = ["subnet-22222222222222222", "subnet-33333333333333333"]

  fqdn                 = "relay-ee.example.com"
  route53_zone_id       = "Z0123456789ABCDEFGHIJ"
  certificate_arn       = "arn:aws:acm:eu-central-1:123456789012:certificate/00000000-0000-0000-0000-000000000000"
  relay_auth_secret_arn = "arn:aws:secretsmanager:eu-central-1:123456789012:secret:netbird-relay-AbCdEf"
  image                 = "netbirdio/relay:0.78.2"

  tags = {
    Environment = "production"
    Service     = "netbird"
  }
}
```

Configure Management with the module outputs:

```yaml
server:
  stuns:
    - uri: "stun:relay-ee.example.com:3478"
      proto: "udp"
  relays:
    addresses:
      - "rels://relay-ee.example.com:443"
    secret: "the-same-secret-value"
```

## Recovery and scaling

The ECS service uses stop-then-start deployments so two instances of the same Relay identity do not overlap. ECS replaces an unhealthy or stopped task. Add capacity or another failure domain by creating another module instance with a separate FQDN rather than increasing the desired count.

## Inputs

| Name | Type | Required | Description |
| --- | --- | --- | --- |
| `name` | `string` | yes | Short resource name for this Relay site. |
| `vpc_id` | `string` | yes | Existing VPC ID. |
| `public_subnet_ids` | `set(string)` | yes | Subnets for the internet-facing NLB. |
| `private_subnet_ids` | `set(string)` | yes | Subnets for the private Fargate task. |
| `fqdn` | `string` | yes | Public Relay/STUN DNS name. |
| `route53_zone_id` | `string` | yes | Existing hosted-zone ID. |
| `certificate_arn` | `string` | yes | Existing ACM certificate covering `fqdn`. |
| `relay_auth_secret_arn` | `string` | yes | ARN of the regional plaintext Relay-auth secret. |
| `image` | `string` | yes | Pinned Relay image reference. |
| `cpu` | `number` | no, `256` | Fargate CPU units. |
| `memory` | `number` | no, `512` | Fargate memory in MiB. |
| `log_retention_days` | `number` | no, `30` | CloudWatch Logs retention. |
| `tags` | `map(string)` | no, `{}` | Additional resource tags. |

## Outputs

| Name | Description |
| --- | --- |
| `relay_uri` | TLS Relay URI to advertise through Management. |
| `stun_uri` | STUN URI to advertise through Management. |
| `service_arn` | ECS service ARN. |
| `load_balancer_arn` | NLB ARN. |
