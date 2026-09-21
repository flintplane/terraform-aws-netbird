# IPv6 support

IPv6 support is optional and currently applies to two modules:

| Module | What `enable_ipv6 = true` changes | Main benefit |
| --- | --- | --- |
| Routing peer | Task ENIs receive IPv6 and permit IPv6 egress | NetBird can establish direct P2P transport over IPv6 |
| Control plane | The public ALB becomes dual-stack and publishes `AAAA` records | IPv6 clients can reach Management, Signal, and Dashboard |

The Relay module remains IPv4-only. This does not prevent direct IPv6 P2P connectivity. Signal can exchange global IPv6 ICE candidates over IPv4, after which peers can communicate directly over IPv6. The IPv4 Relay remains a fallback when direct connectivity fails.

## Caller-owned infrastructure

The modules do not create or modify VPC IPv6 CIDRs, subnet IPv6 CIDRs, route tables, internet gateways, egress-only internet gateways, network ACLs, or ECS account settings. The calling environment must provide them.

Every supplied IPv6-enabled subnet must have an IPv6 `/64` from an internet-routable VPC IPv6 CIDR. Network ACLs must permit the required IPv6 traffic and return path. The default network ACL already permits this; restrictive network ACLs need explicit IPv6 rules.

IPv6 does not use an IPv4 NAT Gateway. AWS assigns globally unique IPv6 addresses directly to ENIs, while security groups, network ACLs, and subnet routes control reachability.

## Routing peer

Set:

```hcl
enable_ipv6 = true
```

The supplied subnets must:

- have IPv6 `/64` ranges;
- automatically assign IPv6 addresses to new ENIs; and
- route `::/0` to an internet gateway when public, or to an egress-only internet gateway when private.

The ECS service keeps `assign_public_ip = false`. This prevents a public IPv4 address on the task ENI but does not prevent automatic IPv6 assignment.

The module permits IPv6 egress from routing-peer task ENIs and deliberately creates no inbound IPv6 rule. NetBird initiates ICE connectivity checks through outbound traffic, and the stateful task security group permits the corresponding return traffic. An egress-only internet gateway adds a subnet-level restriction against unrelated internet-initiated traffic when private subnets are used.

The regional ECS `dualStackIPv6` account setting must be enabled so ECS can assign IPv6 addresses to `awsvpc` task ENIs. Check it with:

```bash
aws ecs list-account-settings \
  --region eu-central-1 \
  --name dualStackIPv6 \
  --effective-settings
```

Enable the account default when necessary:

```bash
aws ecs put-account-setting-default \
  --region eu-central-1 \
  --name dualStackIPv6 \
  --value enabled
```

Manage this shared account setting once in the environment infrastructure or through a controlled administrative procedure, rather than in each module instance.

IPv6 is the transport underlay between NetBird peers. Resources reached through the routing peer can continue to use IPv4 and the existing forwarding and masquerade path.

## Control plane

Set:

```hcl
enable_ipv6 = true
```

Every supplied public ALB subnet must have an IPv6 `/64` and route `::/0` to an internet gateway. Restrictive network ACLs must permit IPv6 HTTPS and return traffic.

The module:

- changes the public ALB to `dualstack`;
- permits inbound IPv6 HTTPS; and
- creates `AAAA` aliases for Management, Signal, and Dashboard.

The ALB continues to use IPv4 target groups. Management, Signal, Dashboard, and RDS remain IPv4 and do not require automatic ENI IPv6 assignment or the ECS `dualStackIPv6` account setting.

## Why Relay remains IPv4-only

The Relay module uses one internet-facing NLB for two protocols:

- Relay over TCP/443; and
- embedded STUN over UDP/3478.

AWS does not allow an IPv4 target group with a UDP listener on a `dualstack` NLB. A single dual-stack NLB therefore cannot retain the existing IPv4 STUN target path while also adding a same-family IPv6 STUN target path.

Forwarding IPv4 UDP clients to an IPv6 target group is not an equivalent substitute: cross-family forwarding does not preserve the IPv4 client address, while STUN must observe and report that address accurately. Native IPv6 support for the combined Relay/STUN endpoint therefore requires a different frontend design. It is intentionally deferred rather than exposed as a misleading module switch.

This limitation does not affect direct IPv6 P2P:

1. Signal exchanges candidate addresses between peers.
2. Peers with globally reachable IPv6 addresses can select `host/host` IPv6 candidates.
3. Their WireGuard traffic then flows directly over IPv6.
4. The IPv4 Relay is used only if direct connectivity cannot be established.

Relay QUIC on UDP/443 is also intentionally deferred. Adding it requires a separate review of load balancing, TLS termination, certificates, security groups, and target-group behavior.

## Validation

### Routing peer

1. Confirm every routing-peer task ENI has a private IPv4 address and a global AWS IPv6 address.
2. Confirm the client network has working public IPv6.
3. Generate traffic to a resource routed through the peer.
4. Run `netbird status --detail` on the client.
5. Confirm the routing peer reports `Connection type: P2P`, `host/host` candidates, and global IPv6 candidate endpoints.

The global AWS IPv6 address on the task ENI is an underlay address. It is separate from the private NetBird overlay IPv6 address beginning with `fd`. A relayed connection remains expected when UDP is blocked or ICE cannot establish a direct path.

This procedure was verified with a macOS client and ECS Managed Instances routing peers in private subnets using an egress-only internet gateway. The direct path continued to work without IPv6 forwarding sysctls and without an inbound UDP/51820 task-security-group rule.

### Control plane

Verify both DNS families and HTTPS:

```bash
dig +short A management.example.com
dig +short AAAA management.example.com
curl -4 --fail https://management.example.com/api/instance
curl -6 --fail https://management.example.com/api/instance
```

Repeat the DNS checks for Signal and Dashboard. Application-level client and login tests remain necessary because DNS and HTTPS reachability alone do not validate gRPC, WebSocket, or authentication behavior.
