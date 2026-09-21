# NetBird routing-peer module

Deploys one independently replaceable NetBird routing site on Amazon ECS Managed Instances. The Managed Instances run Bottlerocket and the NetBird clients run as separate ECS tasks using `awsvpc` networking.

This module accepts public or private subnets. It optionally gives `awsvpc` task ENIs IPv6 egress through an internet gateway or egress-only internet gateway, which can provide direct NetBird peer connectivity without adding public IPv4 addresses or host networking.

## Owned resources

- Dedicated ECS cluster with enhanced Container Insights
- ECS Managed Instances capacity provider using Bottlerocket
- On-Demand Managed Instances selected by ECS for the x86-64 task workload
- ECS service and task definition
- ECS infrastructure, instance, and task-execution IAM roles
- Dedicated KMS key for ECS managed storage
- Separate security groups for Managed Instances and task ENIs
- CloudWatch log group

The module does not create a VPC, subnets, NAT gateways, VPC endpoints, NetBird setup keys, NetBird groups, Networks, resources, or access policies.

## Runtime model

The default service runs two NetBird tasks. A placement constraint keeps them on distinct Managed Instances. Managed Instances automatically tries to spread service tasks across the Availability Zones represented by the supplied subnets, subject to available capacity.

The capacity provider leaves instance selection to ECS. ECS chooses cost-optimized general-purpose capacity that satisfies the x86-64 task definition and service requirements. Each host currently runs one 256-CPU-unit, 512-MiB NetBird task because the distinct-instance constraint provides failure isolation. AWS bills the whole selected EC2 instance; monitor the selected types and cost because the module does not impose an upper instance-size limit.

Each task:

- receives a private IPv4 address on its own ENI and, when enabled by the caller and environment, a global IPv6 address;
- mounts `/dev/net/tun`;
- receives `NET_ADMIN`, `SYS_ADMIN`, and `SYS_RESOURCE` Linux capabilities;
- starts with IPv4 forwarding and marked-source validation enabled in its network namespace;
- reads the setup key from Secrets Manager at startup;
- registers an independent NetBird peer;
- stores its peer key and configuration only in its disposable container filesystem.

The setup key must create ephemeral peers and auto-assign them to one stable routing-peer group. Policies and Networks should reference that group rather than individual ECS peers.

The module intentionally leaves task egress unrestricted. NetBird Networks and resource policies define logical access, while destination security groups define accepted ports. Restricting task egress by CIDR would duplicate NetBird resource configuration and could prevent new Networks from working until Terraform was updated.

## Requirements

- Two or more existing subnets in the same VPC
- Outbound access from the subnets through NAT or suitable VPC endpoints
- A pinned NetBird client image, such as `netbirdio/netbird:0.79.0`
- A reusable NetBird setup key stored in Secrets Manager
- The secret and module in the same AWS region
- The secret encrypted with the default `aws/secretsmanager` KMS key

The subnets must let the Managed Instances and tasks reach ECS, the image registry, CloudWatch Logs, Secrets Manager, NetBird Management, Signal, Relay/STUN, and the routed destinations.

### Optional IPv6

Set `enable_ipv6 = true` to allow IPv6 egress from task ENIs. This supports a NAT-free direct NetBird transport when the remote peer also has working IPv6. It does not remove IPv4 or Relay fallback.

The caller must provide all shared IPv6 infrastructure:

- an internet-routable IPv6 CIDR on the VPC;
- an IPv6 `/64` and automatic IPv6 assignment on every supplied subnet;
- `::/0` to an internet gateway for public subnets, or to an egress-only internet gateway for private subnets;
- network ACLs that permit IPv6 egress and return traffic; and
- the ECS `dualStackIPv6` account setting enabled in this account and region.

The ECS service keeps `assign_public_ip = false`. A task in a public subnet can therefore receive an automatically assigned IPv6 address without receiving a public IPv4 address.

The module does not create or change those shared resources or account settings. It adds IPv6 egress to the task security group but deliberately creates no inbound rule. NetBird's ICE negotiation establishes the direct UDP path through outbound traffic, and the stateful security group admits its return traffic while rejecting unrelated internet-initiated flows. An egress-only internet gateway adds a subnet-level inbound restriction when private subnets are used.

This option enables IPv6 as the NetBird transport underlay. It does not enable kernel IPv6 forwarding or claim support for routing IPv6 Network resources through the task. IPv4 resources continue to use the existing forwarding and masquerade path inside the IPv6-carried NetBird tunnel.

See the repository [IPv6 guide](../../IPV6.md) for the account-setting commands, complete decision record, testing procedure, and rollback behavior.

## Example

```hcl
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
    Service = "netbird"
  }
}
```

## Prepare NetBird

### 1. Create the stable routing-peer group

In the NetBird Dashboard, open **Access Control → Groups** and create a group such as `routing-peers-central`.

### 2. Create the setup key

Open **Settings → Setup Keys → Create Setup Key** and configure:

- **Name:** `routing-peers-central`
- **Type:** Reusable
- **Ephemeral peers:** Enabled
- **Auto-assign groups:** `routing-peers-central`
- **Usage limit:** High enough for routine task and host replacements
- **Expiration:** Long enough for operations, with monitoring before expiry

An expired setup key does not disconnect registered peers, but new replacement tasks cannot register. Auto-assigned groups apply only when a peer first registers.

### 3. Store the setup key in Secrets Manager

Create the secret in the same region as the module. Store the setup key as the complete plaintext secret value, not as a JSON property. Select the default `aws/secretsmanager` encryption key.

The AWS Console path is **Secrets Manager → Store a new secret → Other type of secret → Plaintext**.

Alternatively, read the value without echoing it and create the secret with the AWS CLI:

```bash
printf 'NetBird setup key: '
read -s NETBIRD_SETUP_KEY
printf '\n'

printf '%s' "$NETBIRD_SETUP_KEY" | aws secretsmanager create-secret \
  --name netbird/routing-peer \
  --secret-string file:///dev/stdin \
  --query ARN \
  --output text

unset NETBIRD_SETUP_KEY
```

Pass only the returned ARN to `setup_key_secret_arn`.

The Terraform caller needs `secretsmanager:ListSecretVersionIds` for this secret. Terraform reads version metadata to detect `AWSCURRENT`; it does not read the setup-key value.

Existing peers do not need the setup key again. The module resolves the secret's `AWSCURRENT` version ID, so changing the value produces a new task definition and controlled ECS deployment on the next apply. Use a reusable key that allows the resulting replacement peers to register.

## Configure routing in NetBird

After deployment, confirm that the expected number of connected peers appears in the `routing-peers-central` group.

1. Open **Network Routing → Networks** and add a Network, for example `AWS through central VPC`.
2. Select `routing-peers-central` as its routing-peer group.
3. Add a low-risk test resource first, preferably one host expressed as `/32`.
4. Assign the resource to a resource group such as `aws-test-resources`.
5. Keep **Masquerade** enabled. Destinations will see the task ENI address and do not need a return route for the NetBird address range.
6. In the resource's **Access Control** tab, create a policy from the intended user or peer group to `aws-test-resources`, limited to the required protocols and ports.
7. Allow those ports in the destination AWS security group from the central VPC or routing subnet CIDR, according to the existing network-security model.

Network-resource policies grant access to resources behind the routing peers. They do not grant access to the routing-peer container itself.

After the `/32` test succeeds, add larger VPC CIDRs or more narrowly scoped resources. Use separate resource groups when different teams or services require different policies.

## Verify availability

1. Confirm every ECS task appears as a connected, ephemeral peer in the routing group.
2. Connect to the test resource from an authorized NetBird client.
3. Confirm the destination sees a routing-peer task ENI as the source address.
4. Stop one ECS task and verify that traffic recovers through the remaining routing peer.
5. Confirm ECS creates a replacement and it joins the routing group.
6. Confirm the stopped ephemeral peer disappears from NetBird after its offline cleanup period.

When IPv6 is enabled, also confirm each task ENI has a global AWS IPv6 address. From a client with public IPv6, generate routed traffic and run `netbird status --detail`. A successful direct path reports `Connection type: P2P` with IPv6 candidate endpoints. An `fd...` NetBird address is the private overlay address and does not prove that the task received a public underlay IPv6 address.

The container health check verifies that the local NetBird daemon is responsive. Management, Signal, Relay, and route availability should also be monitored from NetBird because restarting every routing peer during a control-plane interruption would reduce availability.

Terraform does not wait for the ECS service to reach steady state. A successful apply may precede Managed Instances provisioning and peer registration. Confirm the running task count, ECS service events, CloudWatch logs, and connected peers before considering the routing site ready.

When the capacity provider is first created or replaced, the module waits 30 seconds before asking ECS to create the service. The ECS API reports a Managed Instances capacity provider as created before it reaches `ACTIVE`, and the AWS provider currently has no readiness waiter. If AWS activation exceeds this delay, rerun apply after the provider becomes active. Avoid replacing this with a CLI polling provisioner, which would add an undeclared AWS CLI runtime dependency and imperative behavior.

## Security notes

- ECS Exec is disabled.
- Managed Instances expose no SSH service and have no inbound security-group rules.
- Task ENIs have no inbound security-group rules. With IPv6 enabled, stateful return traffic for task-initiated IPv6 flows remains allowed.
- The NetBird task deliberately has powerful networking capabilities. The image reference must remain pinned and should preferably use an immutable digest after testing.
- `SYS_ADMIN` follows NetBird's documented container routing-peer example. Test removing it in a later hardening milestone.
- Local NetBird state is intentionally ephemeral. Never copy `default.json` between peers because it contains the peer private key.
- Public direct-connectivity mode requires a separate host-networking design and is outside this milestone.

## Inputs

| Name | Type | Required | Description |
| --- | --- | --- | --- |
| `name` | `string` | yes | Short resource name for this routing site. |
| `vpc_id` | `string` | yes | Existing VPC ID. |
| `subnet_ids` | `set(string)` | yes | At least two subnets for hosts and task ENIs. |
| `enable_ipv6` | `bool` | no, `false` | Enable task-ENI IPv6 egress for direct NetBird transport; shared IPv6 infrastructure remains caller-owned. |
| `image` | `string` | yes | Pinned NetBird client image reference. |
| `management_url` | `string` | yes | Management HTTPS origin, without a path. |
| `setup_key_secret_arn` | `string` | yes | ARN of the plaintext setup-key secret. |
| `desired_count` | `number` | no, `2` | Number of ephemeral routing peers. |
| `log_retention_days` | `number` | no, `30` | CloudWatch Logs retention. |
| `tags` | `map(string)` | no, `{}` | Additional resource tags. |

## Outputs

| Name | Description |
| --- | --- |
| `cluster_arn` | Dedicated ECS cluster ARN. |
| `capacity_provider_arn` | Managed Instances capacity-provider ARN. |
| `service_arn` | Routing-peer ECS service ARN. |
| `instance_security_group_id` | Bottlerocket host security-group ID. |
| `task_security_group_id` | Task ENI security-group ID. |
| `log_group_name` | Routing-peer log-group name. |
| `managed_storage_kms_key_arn` | KMS key ARN for ECS managed storage. |
