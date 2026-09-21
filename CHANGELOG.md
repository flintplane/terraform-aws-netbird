# Changelog

All notable user-visible changes to this repository are recorded here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and releases follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## Unreleased

## [0.1.0] - 2026-09-21

### Added

- Control Plane module with separate Management, Signal, and Dashboard ECS services, PostgreSQL RDS, embedded identity-provider support, and optional dual-stack public endpoints.
- Relay module for independently deployable Relay and STUN sites on ECS Fargate.
- Routing Peer module using ECS Managed Instances for routed access to existing private networks.
- Architecture, deployment, IPv6, identity-provider, and traffic-auditability documentation.
