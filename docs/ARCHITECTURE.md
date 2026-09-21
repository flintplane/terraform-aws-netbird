# Architecture

## Purpose

This repository packages a self-hosted NetBird deployment as separate AWS application modules. It is intended for organizations that already manage their AWS foundation and want a production-oriented NetBird platform without coupling every component to one runtime or one replacement lifecycle.

The architecture has two layers:

1. **The baseline platform:** Control Plane plus one or more Relay sites.
2. **Optional private-network access:** independently deployed Routing Peer sites.

The modules are independently usable, but they are designed to compose into this reference architecture.

## Context

A compact, combined deployment is easy to start but gives Management, Signal, Dashboard, Relay, and local persistence a shared failure and scaling boundary. That trade-off becomes less attractive when the deployment must support controlled upgrades, external identity, durable state, multiple network locations, or formal operational review.

Traditional remote-access VPNs also commonly expose a large routed network through one gateway. Replacing that model all at once can require changes to applications, cluster ingress, access policy, and audit processes. This design supports an incremental transition: start with NetBird routing peers for existing private networks, then move selected services toward direct or workload-local NetBird connectivity.

## Goals

- Isolate components with different scaling and recovery characteristics.
- Store Management and identity data in durable PostgreSQL storage.
- Prefer AWS-managed runtimes over general-purpose hosts that require interactive administration.
- Keep application secrets out of ordinary Terraform inputs.
- Use explicit network and identity trust boundaries.
- Reuse existing AWS networking and DNS rather than owning an environment.
- Allow Relay and routing sites to be added or replaced independently.
- Support incremental adoption from routed access toward workload-local connectivity.

## Non-goals

- Creating AWS accounts, VPCs, subnets, gateways, hosted zones, certificates, or Terraform backends.
- Managing NetBird groups, policies, Networks, resources, or external identity-provider objects through Terraform.
- Providing active-active Management or Signal before their horizontal behavior is verified.
- Providing lossless traffic-flow audit events in the Community deployment.
- Supporting routed IPv6 resources through the Routing Peer module.
- Providing native IPv6 Relay, TURN, or Relay QUIC with the current Relay frontend.
- Installing NetBird into application workloads or Kubernetes clusters.

## Component boundaries

### Control Plane

The Control Plane module creates three ECS Fargate services behind one public Application Load Balancer:

- **Management** owns NetBird configuration, peer state, API behavior, activity events, and the embedded identity broker.
- **Signal** coordinates peer connection establishment.
- **Dashboard** provides the administrative web interface.

Each service has a separate task definition, ECS service, target groups, security group, execution role, and log group. Sharing an ECS cluster and ALB reduces unnecessary infrastructure while preserving runtime and deployment isolation.

Management uses a module-owned PostgreSQL RDS instance. The Management store, activity store, and embedded identity-provider store share that database service but maintain separate application tables. RDS storage and generated module secrets use separate module-owned KMS keys.

### Relay sites

One Relay module instance represents one advertised Relay identity and failure domain. Its Fargate task remains private, while an internet-facing Network Load Balancer and public DNS name expose:

- Relay over TLS on TCP/443; and
- embedded STUN on UDP/3478.

Additional capacity or regional diversity is added through another module instance with another stable DNS name. Increasing the task count behind one Relay identity is deliberately avoided until overlap and connection-draining behavior are verified.

### Routing sites

One Routing Peer module instance represents one independently replaceable routing site in one VPC and region. NetBird clients run as privileged `awsvpc` tasks on ECS Managed Instances backed by Bottlerocket-oriented managed capacity.

Every task registers as an independent ephemeral NetBird peer. A stable NetBird group is the routing identity: Networks and policies refer to the group rather than to disposable peers. The caller chooses the replica count according to its availability, cost, and connection-recovery requirements.

Routing peers masquerade traffic by default. A destination therefore sees the routing-peer task address and does not require a return route for the NetBird overlay range. This simplifies adoption but limits destination-side attribution to the routing site rather than the initiating user.

## Traffic flows

### Control-plane traffic

Clients and administrators reach Management, Signal, and Dashboard through HTTPS on the public ALB. TLS terminates at the ALB, which forwards to separate protocol-specific target groups. Management reaches PostgreSQL over the private VPC path.

The ALB is the only permitted inbound source for the ECS services. Management trusts forwarded client addresses only when the immediate source belongs to the IPv4 CIDRs of the supplied ALB subnets. The configured proxy count is one because the reference path contains one application proxy hop.

If another proxy layer is introduced, the trusted networks and proxy-hop count must be reviewed rather than inherited unchanged.

### Peer traffic

Signal exchanges connection candidates; it does not carry the WireGuard data path. Peers attempt direct P2P connectivity first. STUN helps peers discover usable addresses. Relay carries encrypted peer traffic when a direct path cannot be established.

Control-plane reachability, Signal coordination, STUN discovery, and the eventual WireGuard data path are separate concerns. A peer can establish a direct IPv6 data path even when Management, Signal, or STUN was reached over IPv4.

### Routed-resource traffic

A client establishes a NetBird tunnel to one routing peer selected for the Network. The routing peer forwards the packet to the private destination and, when masquerading is enabled, translates the source to its task address. Existing VPC routes, peering, transit connectivity, network ACLs, and destination security groups remain caller-owned parts of the path.

The module does not infer routed CIDRs from AWS route tables. NetBird resources and policies remain the authority for what is advertised and who can use it.

## Identity model

The embedded identity provider runs inside Management and acts as NetBird's authentication broker. An external identity provider is configured through the Dashboard and remains NetBird application data rather than Terraform-managed infrastructure.

The deployment owner chooses:

- which external provider to use;
- assignment and group-claim rules;
- when to disable local authentication;
- which identity holds the NetBird Owner role; and
- how break-glass access is governed.

The Control Plane module supports these choices without prescribing a particular provider. The companion Okta guide is one implementation example.

## Security and secret boundaries

- Runtime images must be pinned and should use immutable digests after testing.
- Relay authentication and routing setup-key values are read by ECS directly from Secrets Manager.
- Terraform reads secret version metadata to trigger controlled task replacement but does not read those externally supplied secret values.
- The control plane creates its database credentials and stable cryptographic material as module-owned secrets.
- RDS storage uses a dedicated customer-managed KMS key rather than the AWS-managed RDS key.
- ECS roles are separated by service and limited to their runtime dependencies.
- Routing hosts expose neither SSH nor ECS Exec and have no inbound security-group rules.
- Routing tasks retain elevated networking capabilities because they create tunnels, firewall rules, and forwarding state. This makes image provenance and pinning especially important.

The Control Plane uses Terraform ephemeral values and write-only provider arguments so its generated secret plaintext is not persisted in plan or state files. Terraform state remains sensitive because it describes the security architecture and contains resource identifiers and metadata. The consuming environment is responsible for encrypted remote state and tightly controlled state access.

## Availability and recovery model

The architecture favors simple replacement and durable external state over distributed application state:

- Management and Signal are singleton services with stop-then-start deployments.
- Dashboard replicas can use ordinary rolling replacement.
- A Relay site is a singleton; multiple sites provide independent fallback identities.
- PostgreSQL can be Single-AZ or Multi-AZ according to the caller's recovery objective.
- A routing site can run one or more disposable peers according to the caller's availability and session-recovery requirements.

Established peer tunnels do not continuously traverse Management or Signal, but control-plane interruption affects login, synchronization, policy changes, and new connection negotiation. Relay replacement can interrupt sessions using that Relay. Routing-peer replacement can interrupt routed connections even when another peer is available because existing transport and translation state is not shared.

Terraform does not wait for ECS services to reach steady state. Operational readiness requires application-level verification after apply.

## IPv6 scope

IPv6 is optional and incremental:

- The public control-plane ALB can become dual-stack while its targets remain IPv4.
- Routing-peer task ENIs can use global IPv6 as a direct NetBird transport underlay while routed resources remain IPv4.
- Relay remains IPv4-only with the current combined Relay/STUN NLB design.

AWS does not allow an IPv4 target group behind a UDP listener on a dual-stack NLB. Native Relay IPv6 therefore requires a different frontend rather than a transparent switch on the current module. Relay QUIC is also deferred pending a complete listener, TLS, certificate, and target-group review.

See the repository's [IPv6 guide](../IPV6.md) for requirements and verification.

## Evolution toward workload-local connectivity

Broad routing sites are useful when adopting NetBird around existing private networks. They avoid changing every service during the first migration step, but they retain a shared forwarding point and usually hide the initiating overlay identity from the destination.

A later deployment can move connectivity closer to selected workloads through:

- direct NetBird peers on servers;
- narrower routing sites near an application boundary; or
- Kubernetes integration such as the NetBird Kubernetes operator.

That evolution can reduce the scope of advertised networks, improve policy precision, and improve workload-level attribution. It belongs to the consuming environment and is outside the current Terraform modules.

## Deferred decisions

- Native IPv6 Relay and STUN frontend design.
- Relay QUIC on UDP/443.
- TURN deployment and advertisement.
- Management and Signal horizontal scaling.
- Routing-peer capability reduction, including removal of `SYS_ADMIN` if testing permits it.
- Automated database credential rotation beyond the current controlled version mechanism.
- Alarm thresholds, notification destinations, and broader audit-log export.
- Traffic-event auditability through licensed NetBird Enterprise, a narrow Community extension, or independent telemetry.

The traffic-event options and their evidence limits are recorded in [Traffic-event auditability](../TRAFFIC-EVENTS.md).
