# Contributing

This repository contains reusable Terraform modules. Changes should keep environment-specific infrastructure and identifiers in consuming configurations.

## Branch model

`main` is the only permanent branch and should remain releasable. Use a short-lived branch for every change and merge it through a pull request after validation.

Suggested branch names:

- `feature/<subject>` for backward-compatible capabilities;
- `fix/<subject>` for corrections;
- `docs/<subject>` for documentation-only work; and
- `release/<version>` only for preparing a specific release.

Automation may use its required branch namespace. Do not create a permanent `develop` branch. A second long-lived branch adds merge and release coordination without providing useful isolation while only one release line is supported.

Create a maintenance branch such as `support/1.x` only when the project explicitly promises fixes for an older major release alongside a newer one.

## Changes

Before implementation, discuss changes to public module inputs and outputs. Treat these as part of the public API, together with:

- input defaults and validation;
- output meaning;
- resource addresses and state migrations;
- changes that replace infrastructure;
- required Terraform and provider versions; and
- observable runtime or security behavior.

Keep commits focused and write messages in the imperative form. Conventional prefixes such as `feat:`, `fix:`, `docs:`, `refactor:`, and `chore:` are encouraged because they make release history easier to scan; version selection remains a deliberate maintainer decision.

## Pull requests

A pull request should explain the resulting behavior, compatibility impact, operational consequences, and validation. Infrastructure changes should include a representative consumer plan when practical, with account identifiers and sensitive values removed.

CI checks Terraform formatting and validates every module. Contributors should run the same checks locally:

```shell
terraform fmt -check -recursive

for module in modules/control-plane modules/relay modules/routing-peer; do
  terraform -chdir="$module" init -backend=false -input=false
  terraform -chdir="$module" validate
done
```

Do not run `terraform apply` from this repository. Deployment testing belongs to a consuming environment.

The repository does not commit dependency lock files for child modules. CI resolves versions within each module's declared constraints, while a consuming root module owns its dependency lock file and pins the exact provider selections used for deployment.

## Changelog

Add user-visible changes to the `Unreleased` section of [`CHANGELOG.md`](./CHANGELOG.md). Changelog entries should describe the effect on module consumers rather than the implementation steps.

Routine wording corrections and internal refactoring without consumer-visible effects do not require an entry.

## Repository settings

Configure a GitHub branch ruleset for `main` that:

- requires changes to arrive through pull requests;
- requires the Terraform validation checks to pass;
- requires at least one approval when another maintainer is available;
- dismisses stale approvals after new commits;
- blocks force pushes and deletion; and
- limits bypass permission to repository maintainers responsible for recovery.

Configure a tag ruleset for `v*` that limits tag creation and deletion to release maintainers. GitHub settings are intentionally kept outside Terraform in this repository because repository ownership and organization policy differ between consumers.

## Releases

All modules share one repository version. Releases are immutable semantic-version tags created from `main`. See [`RELEASING.md`](./RELEASING.md) for version selection, internal release candidates, and the stable release procedure.
