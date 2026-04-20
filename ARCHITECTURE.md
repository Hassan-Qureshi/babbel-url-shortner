# Architecture Decision Records

This document records the significant architectural decisions made for the URL shortener service. Each ADR follows the [Michael Nygard format](https://cognitect.com/blog/2011/11/15/documenting-architecture-decisions): Status, Context, Decision, Consequences.

---

## Table of Contents

| #                                                           | Title | Status    |
|-------------------------------------------------------------|-------|-----------|
| [ADR-000](#adr-000-shared-vpc-as-a-prerequisite) | Shared VPC as a prerequisite | ✅ Decided |
| [ADR-001](#adr-001-serverless-on-aws-lambda)                | Serverless on AWS Lambda | ✅ Decided |
| [ADR-002](#adr-002-cache-first-redirect-path)               | Cache-first redirect path | ✅ Decided |
| [ADR-003](#adr-003-redis-errors-are-swallowed)              | Redis errors are swallowed | ✅ Decided |
| [ADR-004](#adr-004-dynamodb-as-primary-store)               | DynamoDB as primary store | ✅ Decided |
| [ADR-005](#adr-005-csprng-short-code-generation)            | CSPRNG short code generation | ✅ Decided |
| [ADR-006](#adr-006-fire-and-forget-hit-counters)            | Fire-and-forget hit counters | ✅ Decided |
| [ADR-007](#adr-009-aws-lambda-powertools-for-observability) | AWS Lambda Powertools for observability | ✅ Decided |
| [ADR-008](#adr-010-zip-deployment-on-arm64)                 | Zip deployment on arm64 | ✅ Decided |
| [ADR-009](#adr-012-terraform-module-hierarchy)              | Terraform module hierarchy | ✅ Decided |
| [ADR-010](#adr-013-cloudfront-plus-waf-at-the-edge)         | CloudFront + WAF at the edge | ✅ Decided |
| [ADR-011](#adr-014-multi-environment-promotion-pipeline)    | Multi-environment promotion pipeline | ✅ Decided |

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

## ADR-001: [Compute Layer] Serverless on AWS Lambda

**Status:** Accepted

### Context

The URL shortener has two distinct workloads:

- **Writes** (`POST /shorten`): bursty, low volume, latency-tolerant.
- **Reads** (`GET /{code}`): high volume, latency-critical, heavily cacheable.

We needed to choose between always-on compute (ECS/EKS/EC2) and event-driven compute (Lambda).

### Options Considered

| Option | Pros | Cons                                                |
|--------|------|-----------------------------------------------------|
| **Lambda** | Zero idle cost, auto-scaling, no patching | Cold starts, 15 min timeout, zip size limit         |
| **ECS Fargate** | No cold starts, long-running | Minimum cost even at zero traffic, more IaC  effort |
| **EKS** | Full k8s ecosystem | Massive operational overhead for a simple service   |

### Decision

Use **AWS Lambda** with the native Python runtime and zip deployment.

### Consequences

- **+** Zero cost at zero traffic; perfect for dev/staging environments.
- **+** Automatic scaling from 0 to thousands of concurrent executions.
- **+** No OS patching, no container image managemetn
- **−** Cold starts add ~200–500 ms on first invocation (mitigated by Provisioned Concurrency in prod if needed).
- **−** 250 MB unzipped deployment package limit (sufficient for this service)

---

## ADR-002: Cache-first redirect path

**Status:** Accepted

### Context

The redirect handler (`GET /{code}`) is the hot path. Every millisecond of latency is visible to the end user. DynamoDB single-item reads take 2–5 ms, but ElastiCache Redis reads take < 1 ms from within the same VPC.

### Decision

The redirect handler checks **Redis first**, then falls back to **DynamoDB** on a cache miss. On a miss, the result is written back to the cache for subsequent requests. In short, the read through cache pattern will be used.

```
Request → Redis GET → hit? → 301 redirect
                    → miss? → DynamoDB GET → found? → Redis SET + 301 redirect
                                           → not found? → 404
```

### Consequences

- **+** DynamoDB read capacity is only consumed on cache misses.
- **+** Stale data for up to `max-age` seconds (120 seconds default) after a URL is deleted or expires.
- **−** Adds ElastiCache as an infrastructure dependency (Reason mentioned in ADR-003, it is for fault tolerance).

---

## ADR-003: Redis errors are swallowed

**Status:** Accepted

### Context

ElastiCache can experience transient failures (network blips, failover, patching). If the cache is unavailable, should the redirect handler return an error or fall through to DynamoDB?

### Alternatives Considered

1. **Fail open**: swallow Redis errors, fall through to DynamoDB (The logic needs to be handled in the code)
2. **Fail closed**: return 503 when cache is unavailable. (Bad user experience during outages, but protects DynamoDB from overload)
3. **Circuit breaker**: track failure rates, switch to DynamoDB-only mode. (Complex to implement correctly, risk of flapping between modes)

### Decision

**Fail open.** Redis operations (`get`, `set`) are wrapped in `try/except` blocks that log a warning and return `None` or do nothing. The cache is treated purely as a performance optimisation, never as a correctness requirement.

```python
def get(self, key: str) -> str | None:
    try:
        return self._client.get(key)
    except redis.RedisError:
        logger.warning("redis get failed, falling through to DynamoDB", ...)
        return None
```

### Consequences

- **+** A Redis outage never causes a user-visible error.
- **+** Follows KISS principal, Simpler than a circuit breaker, fewer states to reason about.
- **−** During a Redis outage, all requests hit DynamoDB (ensure DynamoDB capacity is sufficient).
- **−** Warning log volume spikes during outages (CloudWatch alarm on `CacheMiss` metric will cover this).

---

## ADR-004: [Data Layer] DynamoDB as primary store

**Status:** Accepted

### Context

The data model is simple: a single table keyed by `code` (short code string). Access patterns are:

1. **Write**: `PUT` with conditional check (code must not exist).
2. **Read**: `GET` by partition key.
3. **Counter**: `UPDATE ADD` for hit counts.
4. **Expiry**: TTL-based automatic deletion.

### Options Considered

| Option               | Pros | Cons |
|----------------------|------|------|
| **DynamoDB**         | Single-digit ms reads, TTL, on-demand billing, fully managed | No SQL, limited query flexibility |
| **Aurora Serverles** | Full SQL, complex queries | Minimum cost, VPC-only, more IaC |


### Decision

Use a **single DynamoDB table** with:
- Partition key: `code` (String)
- GSI on `created_by` for listing a user's URLs, if needed in furture, but not required at this time. If we want to list all URLs created by a specific user, we can't do that without a full table scan.
- TTL attribute `expires_at` for automatic expiry
- On-demand (PAY_PER_REQUEST) billing in all environments. Later on in production provisioned capacity with auto-scaling, can be used if needed based on traffic patterns)
- Point-in-time recovery enabled in production
- Server-side encryption enabled

### Consequences

- **+** Zero capacity planning on-demand scales automatically.
- **+** TTL handles expiry without a cron job or sweeper.
- **+** Conditional writes prevent duplicate codes without distributed locking.
- **−** No ad-hoc SQL queries, would need to export to S3/Athena for analytics.

---

## ADR-005: CSPRNG short code generation

**Status:** Accepted

### Context

Short codes must be:
1. **Unique**: no two URLs share a code.
2. **Unpredictable**: users should not be able to enumerate existing codes.
3. **Short**: 6 characters is the default (62^6 ≈ 56 billion combinations).

### Alternatives Considered

| Option | Pros | Cons |
|--------|------|------|
| **`secrets.choice` (CSPRNG)** | Cryptographically random, unpredictable | Requires collision check |
| **`random.choice` (PRNG)** | Fast | Predictable with seed, not security-safe |

### Decision

Use **`secrets.choice`** from Python's `secrets` module to generate a random base62 string. Collision is handled by checking DynamoDB before `PUT`, with up to 3 retries.

### Consequences

- **+** Codes are cryptographically unpredictable.
- **+** No global state or counter needed.
- **−** Theoretical collision probability: at 1 billion codes, collision chance per generation is ~1.8%, handled by retry.
- **−** Different URLs always get different codes (no deduplication). This is by design, the same long URL can have multiple short codes with different expiry dates.

---

## ADR-006: Fire-and-forget hit counters

**Status:** Accepted

### Context

Every redirect should increment a hit counter in DynamoDB. However, the `UPDATE` call takes 2–5 ms and should not be added to the user-facing latency of the redirect response.

### Decision

Hit-count increments run in a **Python daemon thread** (`threading.Thread(daemon=True)`). The redirect handler returns the 301 immediately, and the counter update happens asynchronously. If the thread fails, the error is logged but never propagated.

### Consequences

- **+** Hit counter overhead is invisible to the end user.
- **+** Daemon threads are terminated when Lambda finishes meaning no resource leaks.
- **−** Hit counts may be slightly under-counted if Lambda freezes before the thread completes. (Not super critical)
- **−** Under extreme concurrency, many threads are spawned.

---

## ADR-007: AWS Lambda Powertools for observability

**Status:** Accepted

### Context

Lambda functions need structured logging and custom CloudWatch metrics. We could build this ourselves or use a library.

### Decision

Use **AWS Lambda Powertools for Python** for all observability:

- `Logger`: structured JSON logging with automatic `request_id` injection.
- `Metrics`: CloudWatch EMF (Embedded Metric Format) with `@metrics.log_metrics`.
- `APIGatewayRestResolver`: routing for API Gateway events.

> **Note:** X-Ray tracing via `Tracer` is supported by Powertools but not enabled at this time. The Terraform `enable_xray_tracing` variable defaults to `false` and can be flipped when tracing is needed.

### Consequences

- **+** One library replaces 4-5 bespoke solutions.
- **+** Cold start metric emitted automatically (`capture_cold_start_metric=True`).
- **+** Consistent log format across all functions.
- **-** Adds ~5 MB to the deployment package (acceptable within the 250 MB limit).
- **−** Tight coupling to AWS (acceptable since we're all-in on AWS Lambda).

---

## ADR-008: Zip deployment on arm64

**Status:** Accepted

### Context

Lambda supports two deployment modes: **zip packages** (with a native runtime) and **container images** (up to 10 GB). We need to choose which approach to use and which CPU architecture.

### Alternatives Considered

| Option | Pros | Cons |
|--------|------|------|
| **Zip + native runtime** | Fastest cold start, simplest CI, smallest artifact | 250 MB limit, no custom OS packages |
| **Container image** | Full control, up to 10 GB, custom binaries | Slower cold start (~500 ms more), ECR dependency |
| **x86_64** | Broadest compatibility | Higher cost per ms |
| **arm64 (Graviton2)** | 20% cheaper, often faster | Some native packages may not have arm64 wheels |

### Decision

Use **zip deployment** with the **native Python runtime**.

### Consequences

- **+** Fastest cold starts (~100–300 ms vs ~500–800 ms for containers).
- **+** 20% lower compute cost on arm64.
- **+** No ECR repository to manage.
- **−** Must ensure all pip dependencies have arm64 wheels (all current deps do).
- **−** Cannot install system-level packages (not needed for this service).

---

## ADR-009: Terraform module hierarchy

**Status:** Accepted

### Context

The infrastructure spans 6 AWS servics across 3 environments. We need a structure that is DRY, testable, and easy to reason about.

### Decision

Followed the **Anton Babenko / terraform-best-practices.com** module hierarchy:

```
Resource Module → Infrastructure Module → Composition (Environment)
```

Each resource module (dynamodb, elasticache, lambda, api-gateway, cloudfront-waf, monitoring) is self-contained with:

```
main.tf          # Resources
variables.tf     # Inputs (all with descriptions)
outputs.tf       # Outputs (all with descriptions)
versions.tf      # required_providers + required_version
data.tf          # Data sources
tests/           # Not yet implemented
```

Environments (`dev/`, `staging/`, `prod/`) compose modules with environment-specific sizing.

### Consequences

- **+** Changes to one module don't affect others.
- **+** New environments are trivial, copy and adjust tfvars.
- **−** More files than a monolithic `main.tf` (worthwhile trade-off for a production system).

---

## ADR-010: CloudFront + WAF at the edge

**Status:** Accepted

### Context

The redirect endpoint is publicly accessible and could be abused for:
- **DDoS**: overwhelm Lambda/DynamoDB with requests.
- **Enumeration**: iterate short codes to discover URLs.
- **Malicious traffic**: bot networks, known-bad IPs.

### Decision

Place **CloudFront** in front of API Gateway with an **AWS WAF** WebACL containing:

1. **Rate limiting**: 2000 requests per 5-minute window per IP (configurable).
2. **AWS Managed Rules Common Rule Set**: blocks known attack patterns.
3. **AWS Managed Rules IP Reputation List**: blocks known-bad IPs.
4. **Geo-blocking** (optional): block traffic from specified countries. (currently not enabled, but can be added if abuse is observed from specific regions)

CloudFront also caches `301` redirects at the edge (max-age 60 sec), reducing Lambda invocations for popular links.

### Consequences

- **+** DDoS protection without additional cost beyond WAF rules.
- **+** Edge caching reduces Lambda invocations by 80–95% for popular links.
- **+** TLS termination at the edge with TLS 1.2 minimum.
- **−** WAF adds ~$5/month base cost + per-rule charges.
- **−** Cached redirects are stale for up to 60 seconds after deletion.

---

## ADR-011: Multi-environment promotion pipeline

**Status:** Accepted

### Context

Changes must be validated progressively before reaching production to minimise blast radius.

### Decision

Implement a **3-stage promotion pipeline**:

```
dev (auto) → smoke test → staging (auto) → prod (manual approval gate)
```

- **CI** (every PR): lint, type-check, test, terraform validate, trivy, checkov.
- **CD** (push to main): build zips → deploy dev → smoke test → deploy staging → deploy prod.
- **Authentication**: GitHub OIDC → AWS IAM role (no long-lived secrets).
- **Prod gate**: Requires manual approval in the GitHub `production` environment.

### Consequences

- **+** Every change is tested in dev and staging before prod.
- **+** OIDC eliminates long-lived AWS access keys.
- **+** Security scans (trivy + checkov) block vulnerable infrastructure.
- **−** Full pipeline takes ~10 minutes dev → prod (acceptable for this service).

---


## ADR-001: Shared VPC as a prerequisite

**Status:** Accepted

### Context

Lambda (in VPC mode) and ElastiCache both require a VPC with private subnets. We needed to decide whether to create a VPC per environment or share one.

### Alternatives Considered

1. **VPC per environment** — each `terraform apply` creates its own VPC, subnets, NAT Gateway.
2. **Single shared VPC** — one VPC created once, all environments reference it via remote state.

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

| Date       | ADR               | Change                                                                               |
|------------|-------------------|--------------------------------------------------------------------------------------|
| 2026-04-19 | ADR-000           | Initial creation with VPC created centrally                                          |
| 2026-04-19 | ADR-001 & ADR-002 | Added the modules for lambda and logic for read through cache                        |
| 2026-04-19 | ADR-004           | Decided to use dynamodb as datastore and added the infra implementation & code logic |
| 2026-04-19 | ADR-003           | Code fixes in case of cache miss or any errors                                       |


