# Examples

These examples are canonical consumer configurations for the repository's three modules:

- [Relay](./relay)
- [Control Plane](./control-plane)
- [Routing Peer](./routing-peer)

They use repository-relative module sources so they can be formatted and validated from a checkout. A real consumer should replace the relative source with an immutable Git tag, for example:

```hcl
source = "git::https://github.com/flintplane/terraform-aws-netbird.git//modules/control-plane?ref=v0.1.1"
```

Private consumers can use an SSH Git URL with the same `//modules/<name>?ref=<tag>` syntax. Do not point production environments at a branch.

The examples intentionally omit provider and backend configuration. The consuming root module owns both.

The examples use one consistent namespace:

- `management.netbird.example.com`
- `signal.netbird.example.com`
- `dashboard.netbird.example.com`
- `relay1.netbird.example.com`
- `nb.internal.example.com`

Replace every placeholder VPC, subnet, hosted-zone, certificate, and secret ARN with caller-owned infrastructure identifiers.

## Composition

Deploy Relay before Control Plane so its advertised addresses are known. If both modules are in one root configuration, connect them directly:

```hcl
module "netbird_relay" {
  # See examples/relay/main.tf.
}

module "netbird_control_plane" {
  # See examples/control-plane/main.tf.

  relay = {
    auth_secret_arn = var.relay_auth_secret_arn
    addresses       = [module.netbird_relay.relay_uri]
    stun_uris       = [module.netbird_relay.stun_uri]
  }
}
```

When the modules live in separate Terraform states or AWS regions, pass the Relay URIs through the consuming environment's normal configuration mechanism. Use regional replicas of the same Relay authentication value and pass the appropriate regional secret ARN to each module.
