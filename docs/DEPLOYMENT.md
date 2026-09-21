# Deployment guide

This guide describes how to compose the repository's modules. Each module README remains the authoritative source for its exact inputs, outputs, owned resources, and operational details.

## Choose the deployment shape

The baseline platform consists of:

1. one Control Plane module instance; and
2. at least one Relay module instance.

Routing Peer module instances are optional. Add them only where clients need routed access to existing private resources.

Before deploying, decide:

| Decision | Typical options | Effect |
| --- | --- | --- |
| Relay sites | One site or multiple regional/network sites | Fallback locality and failure isolation |
| Control-plane database | Single-AZ or Multi-AZ | Cost, recovery time, and database availability |
| Public IPv6 | Disabled or dual-stack Control Plane | Client reachability to public endpoints |
| External identity | Any supported provider configured through NetBird | User lifecycle and authentication policy |
| Local authentication | Retained for break-glass or disabled after bootstrap | Recovery process and local-credential exposure |
| Routing sites | None, one, or several | Which private networks are reachable |
| Routing replicas | One or more per site | Cost and replacement availability; existing sessions can still reset |
| Masquerading | Normally enabled for initial adoption | Return-route simplicity versus destination-side attribution |
| Log retention | Organization-specific | Investigation window and cost |

## Caller-owned prerequisites

### Shared AWS foundation

- AWS account and region selection
- Terraform backend and provider configuration
- Existing VPCs and subnets
- Route tables, internet/NAT/egress-only gateways, VPC peering, transit routing, and network ACLs
- Route 53 hosted zone
- ACM certificate covering the public module endpoints
- Permissions for Terraform to manage the documented module resources

Private task subnets need outbound access through NAT or suitable VPC endpoints for ECS, the image registry, CloudWatch Logs, Secrets Manager, KMS, and other runtime dependencies. Management also needs HTTPS access to the selected external identity provider.

### Relay authentication secret

Create one Relay authentication value for the NetBird deployment and store it in Secrets Manager. Management and every Relay site must use the same value. Do not independently generate a secret for every site.

The Relay README documents creation, regional replication, rotation constraints, and the expected plaintext secret format.

### Naming and certificates

Choose distinct public names for:

- Management API and embedded identity-provider endpoints;
- Signal;
- Dashboard; and
- every Relay site.

The Dashboard name is an administrative interface, while Management is the API and authentication origin used by NetBird clients. Certificates and hosted zones remain caller-owned.

## Recommended sequence

### 1. Deploy a Relay site

Deploy one [`modules/relay`](../modules/relay) instance with public NLB subnets, private task subnets, a certificate, DNS name, pinned Relay image, and the Relay secret ARN.

Record:

- `relay_uri`;
- `stun_uri`; and
- the regional Relay secret ARN.

Verify the ECS task, both target groups, TLS endpoint, STUN endpoint, and CloudWatch startup logs before continuing.

Additional Relay sites can be deployed independently with their own names and infrastructure while sharing the same authentication value.

### 2. Deploy the Control Plane

Deploy [`modules/control-plane`](../modules/control-plane) with:

- public ALB and private task/database subnets;
- Management, Signal, and Dashboard names;
- the certificate and hosted-zone identifiers;
- pinned component images;
- the Relay authentication secret ARN;
- all advertised Relay and STUN addresses; and
- the chosen NetBird DNS and single-account domains.

The module derives Management's trusted proxy networks from the supplied ALB subnet CIDRs. If another application proxy is later inserted into the request path, review the generated trust list and proxy-hop count before deployment.

Wait for the Management, Signal, and Dashboard services and their target groups to become healthy. Terraform apply completion alone is not a readiness signal.

### 3. Bootstrap identity

Use the initial local account to complete bootstrap. Configure and test the external identity provider through the Dashboard before disabling local authentication.

At minimum, verify:

- Dashboard interactive login;
- NetBird client login;
- expected identity and group claims;
- administrative role assignment;
- session logout and expiration; and
- a documented break-glass process.

Provider-specific configuration is application data stored by NetBird. The repository includes an [Okta companion guide](../modules/control-plane/OKTA.md) as one example.

### 4. Enroll test clients

Enroll clients from at least two relevant network environments. Confirm:

- Management and Signal connectivity;
- Relay and STUN availability;
- direct P2P connectivity where expected;
- Relay fallback where direct connectivity is unavailable; and
- DNS names under the selected NetBird peer domain.

Use a narrowly scoped test policy before granting broader access.

### 5. Add an optional routing site

When routed private-resource access is required:

1. Create a stable NetBird routing-peer group.
2. Create a reusable setup key with ephemeral peers and automatic assignment to that group.
3. Store the setup key as the complete plaintext value in Secrets Manager.
4. Deploy [`modules/routing-peer`](../modules/routing-peer) in the chosen VPC and subnets.
5. Confirm every ECS task appears as a connected ephemeral peer in the stable group.
6. Create a NetBird Network and begin with one low-risk `/32` resource.
7. Enable masquerading for the initial test unless the destination network has an explicit overlay return path.
8. Add a narrowly scoped NetBird access policy and matching destination security-group rule.
9. Expand to larger CIDRs only after connectivity, source addresses, policy enforcement, and replacement behavior are understood.

Routing replicas are a deployment decision. More than one peer improves replacement availability, but existing routed sessions can reset or stall when path selection changes because peers do not share tunnel or translation state.

## Production decisions

### Images and upgrades

Use pinned image versions and keep Management, Signal, and Relay on the same NetBird release unless release guidance explicitly permits otherwise. Dashboard has its own release stream. Prefer immutable digests once images have passed deployment testing.

Before an upgrade:

1. review NetBird release and migration notes;
2. verify a recent RDS backup or snapshot;
3. confirm the current Relay secret and identity recovery process;
4. deploy configuration migrations before binary changes when the release instructs it; and
5. plan for singleton service replacement.

After an upgrade, verify identity login, Management and Signal synchronization, direct and relayed peer paths, routed access, task health, and application logs.

### Availability

Choose RDS Multi-AZ, Relay site count, and routing replica count from explicit recovery objectives rather than treating every replica count as automatically safer.

Management and Signal remain singletons in this design. Their tasks are replaceable and state is externalized, but replacement causes a control-plane interruption. Existing peer tunnels may continue; login, synchronization, policy changes, and new connection negotiation can be affected.

### Secrets and state

Externally supplied Relay and setup-key values remain in Secrets Manager and are referenced by ARN. The Control Plane uses ephemeral values and write-only provider arguments so generated secret plaintext is not persisted in Terraform plan or state files. State still contains sensitive infrastructure identifiers and metadata; protect it with encryption, versioning, access logging, and tightly limited administrative access.

### Observability

The modules create CloudWatch log groups but do not choose organization-wide alarms, destinations, dashboards, or SIEM integration. At minimum, monitor:

- ECS desired versus running task counts;
- stopped-task reasons and deployment failures;
- ALB/NLB target health;
- RDS availability, storage, connections, and backup status;
- Management authentication and startup errors;
- Signal and Relay connectivity; and
- routing-peer registration and route availability.

NetBird Community activity events do not provide complete per-flow traffic auditability. See [Traffic-event auditability](../TRAFFIC-EVENTS.md) before making compliance claims about who accessed which routed destination.

## Readiness checklist

Treat a deployment as ready only after confirming:

- all expected ECS services have their desired running task count;
- load-balancer target groups are healthy;
- Management can reach PostgreSQL and complete migrations;
- external identity login works;
- a client reports connected Management and Signal endpoints;
- STUN and Relay report available;
- two authorized peers can exchange traffic;
- one deliberately denied path is denied; and
- every configured routed test resource is reachable only from its intended group.

When IPv6 is enabled, also follow the repository's [IPv6 validation](../IPV6.md#validation) procedure.
