# Releasing

This repository releases the Control Plane, Relay, and Routing Peer modules together. One tag identifies a mutually reviewed repository state even when a release changes only one module.

## Version policy

Tags follow Semantic Versioning and include a `v` prefix:

- `v0.2.1` for a backward-compatible bug fix;
- `v0.3.0` for a backward-compatible capability; and
- `v1.0.0` for the first stable public contract or a later breaking release.

A breaking change includes removing or renaming an input or output, materially changing a default, changing resource addresses without a state migration, increasing requirements incompatibly, or introducing unavoidable replacement that was not part of the previous contract.

Before `v1.0.0`, use minor versions for breaking changes and document them explicitly. The `0.x` phase does not make undocumented breakage acceptable.

Never move, replace, or reuse a published tag. Correct a bad release with a new version.

## Internal release candidates

Use prerelease tags to exercise the exact candidate in internal environments before publishing a stable version:

```text
v0.1.0-rc.1
v0.1.0-rc.2
v0.1.0
```

Consumers pin the candidate exactly. For example:

```hcl
module "control_plane" {
  source = "git::https://github.com/flintplane/terraform-aws-netbird.git//modules/control-plane?ref=v0.1.0-rc.1"
}
```

A Terragrunt consumer of a private GitHub repository can use SSH authentication:

```hcl
terraform {
  source = "git::ssh://git@github.com/flintplane/terraform-aws-netbird.git//modules/control-plane?ref=v0.1.0-rc.1"
}
```

Provide repository access to automation through its GitHub identity, deploy key, or credential helper. Do not place a token in the source URL or Terraform configuration.

Create another candidate tag when the candidate changes. If the final candidate needs no changes, the stable tag may point to the same commit.

## Stable release procedure

1. Confirm all intended changes have been merged to `main` and CI passes.
2. Review every entry under `Unreleased` in `CHANGELOG.md`.
3. Choose the version from the compatibility impact, not merely the number or size of commits.
4. Create a short-lived `release/<version>` branch.
5. Move the accumulated changelog entries into a dated version section and restore an empty `Unreleased` section.
6. Update the README requirements and release notes when Terraform, providers, AWS behavior, or NetBird compatibility changed.
7. Open and merge the release pull request.
8. Verify CI on the resulting `main` commit.
9. Create an annotated tag on that exact commit and push it:

   ```shell
   git switch main
   git pull --ff-only
   git tag -a v0.1.0 -m "Release v0.1.0"
   git push origin v0.1.0
   ```

10. Create a GitHub Release from the tag using the matching changelog section as its notes.
11. Upgrade an internal consuming environment by changing only the pinned tag. Review the plan before applying it.
12. Verify ECS service health, target health, identity login, peer connectivity, Relay fallback, and routed access as applicable.

The tag is the release artifact used by Terraform. A GitHub Release improves discoverability and provides human-readable notes, but it must reference the existing immutable tag.

## Version selection

| Change | Version before 1.0 | Version after 1.0 |
| --- | --- | --- |
| Documentation or compatible bug fix | Patch | Patch |
| New optional input, output, or compatible capability | Minor | Minor |
| Removed input, incompatible default, or unavoidable incompatible migration | Minor | Major |

When uncertain, choose the more conservative version and describe the migration impact.

## Recovery from a bad release

Do not rewrite the tag. Consumers can return to the previous tag while a corrective version is prepared. If infrastructure has already changed, first review whether the earlier code can safely manage the new state.

Release a backward-compatible correction as a patch. If correction requires another breaking interface or state change, release the appropriate minor or major version and provide explicit migration instructions.

## Maintenance branches

Do not create maintenance branches preemptively. Once more than one major line is explicitly supported, branch from the last supported release as `support/<major>.x`, cherry-pick narrowly scoped fixes, and release patches from that branch. Features continue through `main`.
