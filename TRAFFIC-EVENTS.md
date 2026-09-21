# Traffic-event auditability

## Status

This is a future investigation. The repository does not currently implement traffic-event collection, and no implementation option has been selected.

The goal is to obtain useful records of who connected, when, and to which peer or routed resource without coupling the current Relay, control-plane, or routing-peer milestones to an unproven audit pipeline.

## Existing NetBird plumbing

The open NetBird client already contains much of the agent-side traffic-event path:

- the Management protocol defines `FlowConfig`, including a receiver address, authentication material, reporting interval, counters, and an enabled flag;
- the client creates a flow manager during engine startup and passes its logger to the firewall implementation;
- Linux kernel-mode clients can observe flows through conntrack;
- userspace and firewall paths can submit events directly to the flow logger;
- the client aggregates events, sends them through a bidirectional gRPC stream, waits for acknowledgements, and retries unacknowledged events; and
- the public `FlowEvent` schema carries peer public key, timestamps, direction, protocol, addresses, ports, counters, resource IDs, and an optional rule ID.

Relevant upstream sources:

- [`shared/management/proto/management.proto`](https://github.com/netbirdio/netbird/blob/main/shared/management/proto/management.proto)
- [`client/internal/netflow`](https://github.com/netbirdio/netbird/tree/main/client/internal/netflow)
- [`flow/proto/flow.proto`](https://github.com/netbirdio/netbird/blob/main/flow/proto/flow.proto)
- [`flow/client`](https://github.com/netbirdio/netbird/tree/main/flow/client)

The centralized Enterprise implementation adds components that are not present in the public Community deployment: a flow receiver, message transport, enrichment, persistence, query APIs, dashboard views, retention processing, and SIEM streaming. The Enterprise bootstrap script shows a receiver, NATS JetStream, an enricher, and PostgreSQL, but the receiver and enricher implementations are distributed as commercial images.

Community Management does not expose a supported way to populate an enabled `FlowConfig`. A separate passive component cannot inject it into unmodified clients because `FlowConfig` is part of the application-level encrypted Management login and synchronization response.

## Options to investigate

### 1. Licensed NetBird Enterprise

Use the supported Traffic Events implementation and integrate its SIEM output with the organization's audit platform.

This has the lowest custom software burden and the clearest support boundary. Licensing, deployment architecture, retention behavior, export format, and cost would need evaluation.

### 2. Narrow Community Management extension and custom receiver

Add a small, explicit Community Management extension that reads static traffic-flow configuration, signs receiver credentials, and includes the existing `FlowConfig` in normal client login and synchronization responses. Standard NetBird clients could then use their existing collectors and gRPC sender.

Deploy a separate receiver that implements the public `FlowService` protocol. A first version could validate credentials, deduplicate by event ID, acknowledge events, and deliver raw records directly to an AWS service such as Firehose or S3. NATS and a dedicated query database are not prerequisites for a small initial design.

This is the strongest custom option for broad coverage because it can activate reporting on laptops, servers, and routing peers without distributing a custom client. It introduces a Management fork and therefore requires an upgrade, security, licensing, and compatibility strategy.

### 3. Routing-peer client extension and custom receiver

Build a narrowly modified NetBird client image for routing peers that supplies receiver configuration locally and reuses the existing flow manager. This avoids changing Management and is smaller than implementing a separate conntrack collector.

Coverage would be limited. Router-side events can describe routed flows, but reliable user attribution may also require an event from the initiating client before routing and masquerading. This option is better suited to an experiment than to a complete audit design.

The collector lives under Go's `internal` package boundary, so an external program cannot import it directly. Reuse would require a NetBird client fork or an upstream-supported local configuration hook.

### 4. Independent network telemetry

Collect AWS VPC Flow Logs, firewall logs, destination service logs, or conntrack events without using NetBird's flow protocol.

This requires no NetBird fork and can provide useful destination evidence. It usually observes the routing peer's masqueraded address rather than the initiating NetBird user, so correlation with NetBird identity and policy state is weaker. It can complement another option but does not by itself satisfy the intended who-accessed-what record.

### 5. Management-protocol shim

A component in front of Management could theoretically terminate NetBird's encrypted Management protocol, forward requests to the real Management service, insert `FlowConfig`, and re-encrypt responses.

This would reimplement security-critical Management session behavior and place the shim in the control-plane availability path. An ordinary ALB, reverse proxy, or gRPC middleware cannot modify the inner encrypted messages. This option should not be pursued unless upstream creates a supported configuration-extension interface.

## Reliability and evidence limits

The existing client pipeline is useful but should not be assumed to provide lossless audit delivery:

- aggregation and unacknowledged-event storage are in memory;
- a client or task restart can lose buffered events;
- the flow logger has a bounded input channel; and
- receiver acknowledgements and stable event IDs support retries and deduplication but do not create a durable source queue on the client.

Kernel-mode collection also has visibility limits. NetBird documents that policy IDs and blocked events are not reported in some kernel-mode cases. The routing peers use kernel WireGuard, so a design must test exactly which successful, rejected, routed, and masqueraded flows are observed before making compliance claims.

Raw event retention and human-readable attribution are separate concerns. A complete design needs an enrichment process that resolves peer public keys, overlay addresses, resource IDs, groups, policies, and users against Management state while preserving the original immutable event.

## Suggested future experiment

Before designing a Terraform module:

1. Audit the flow code at the exact pinned NetBird version rather than relying on `main`.
2. Confirm the event fields produced for a laptop accessing an IPv4 resource through a masquerading routing peer.
3. Implement a disposable receiver for the public gRPC protocol that records raw events and returns acknowledgements.
4. Activate one test routing peer through the smallest possible client patch and compare its events with VPC Flow Logs and destination logs.
5. Determine whether router-only reporting can preserve user attribution. If it cannot, test a Management extension with an unmodified initiating client.
6. Measure loss behavior during receiver outages, task replacement, client restart, and event bursts.
7. Review upstream licenses and the maintenance obligations of any Management or client fork.

The outcome should decide whether to use Enterprise, build a narrowly scoped custom pipeline, combine NetBird events with AWS telemetry, or leave traffic-event collection outside this repository.
