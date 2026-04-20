# Architecture Decision Records

This document records the significant architectural decisions made for the URL shortener service. Each ADR follows the [Michael Nygard format](https://cognitect.com/blog/2011/11/15/documenting-architecture-decisions): Status, Context, Decision, Consequences.

---

## Table of Contents

| #                                                | Title | Status    |
|--------------------------------------------------|-------|-----------|
| [ADR-001](#adr-001-shared-vpc-as-a-prerequisite) | Shared VPC as a prerequisite | ✅ Decided |

---


## ADR-001: Shared VPC as a prerequisite

**Status:** Accepted

### Context

Lambda (in VPC mode) and ElastiCache both require a VPC with private subnets. We needed to decide whether to create a VPC per environment or share one.

### Alternatives Considered

1. **VPC per environment**: each `terraform apply` creates its own VPC, subnets, NAT Gateway.
2. **Single shared VPC**: one VPC created once, all environments reference it via remote state.

### Decision

Use a **single shared VPC** managed in `terraform/vpc/`, applied once as a prerequisite. The environments read `vpc_id` and `private_subnet_ids` from the VPC's remote state.

Layout:
```
terraform/vpc/           ← apply once
terraform/environments/  ← reads VPC outputs via terraform_remote_state
```

The VPC contains:
- 2 public subnets (one per AZ) with an Internet Gateway
- 2 private subnets (one per AZ) with a single NAT Gateway
- Route tables and associations

### Consequences

- **+** One NAT Gateway instead of three and it saves ~$90/month.
- **+** Simpler networking, no cross-VPC peering or Transit Gateway needed for this assignment
- **+** VPC is stable infrastructure that rarely changes, separating its state avoids accidental destruction during app deploys.
- **−** All environments share the same network boundary (acceptable for a single-account setup; use separate VPCs if environments move to separate AWS accounts).

---

## Revision History

| Date       | ADR                     | Change |
|------------|-------------------------|--------|
| 2026-04-19 | ADR-001 through ADR-001 | Initial creation |



