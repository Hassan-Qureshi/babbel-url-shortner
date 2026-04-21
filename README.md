# URL Shortener

> A serverless URL shortener on AWS built with **Python 3.13**, **Terraform**, **AWS Lambda**, and **DynamoDB** with github actions as cicd.

---

## Architecture

> Full rationale for every decision is recorded in [`ARCHITECTURE.md`](ARCHITECTURE.md).

| Layer | Service | Purpose                                                                        |
|-------|---------|--------------------------------------------------------------------------------|
| **Edge** | CloudFront | Global edge caching for 301 redirects, TLS termination                         |
| **Edge** | WAF | IP rate-limiting (2000 req / 5 min), geo-blocking, AWS managed rule sets       |
| **Compute** | API Gateway (REST) | Route `POST /shorten` and `GET /{code}` to Lambda                              |
| **Compute** | Lambda × 2 | Python on arm64, zip deployment                                                |
| **Data** | DynamoDB | A Primary store which has on-demand billing, TTL expiry                        |
| **Data** | ElastiCache Redis | **Read-through** cache pattern is being used TLS in-transit, encryption at rest |
| **Observe** | CloudWatch + SNS | Dashboard, error count alarms, email alerts |

---

## Quick Start

### Prerequisites

| Tool | Version | Install |
|------|---------|---------|
| Python | ≥ 3.13 | [python.org](https://www.python.org) |
| Poetry | latest | `curl -sSL https://install.python-poetry.org \| python3 -` |
| Terraform | ~> 1.9 | [terraform.io](https://developer.hashicorp.com/terraform/install) |
| AWS CLI | v2 | [aws.amazon.com/cli](https://aws.amazon.com/cli/) |

### Build & Deploy
```bash
# Step 0: one-time VPC setup (shared across all environments)
cd terraform/vpc
terraform init && terraform apply
```

---

## Project Structure

```
url-shortner/
│
├── lambda/                          # Python application
│   ├── pyproject.toml               # Poetry project: deps, black, mypy, pytest
│   ├── src/
│   │   ├── shorten/
│   │   │   ├── __init__.py
│   │   │   └── handler.py           # POST /shorten  → create short URL
│   │   └── redirect/
│   │       ├── __init__.py
│   │       └── handler.py           # GET /{code}    → 301 redirect
│   ├── shared/
│   │   ├── __init__.py
│   │   ├── config.py                # Frozen Config dataclass (from env vars)
│   │   ├── exceptions.py            # URLShortenerError → NotFound / Conflict / Expired
│   │   ├── models.py                # Pydantic v2: URLRecord, ShortenRequest, ShortenResponse
│   │   ├── store/
│   │   │   ├── interface.py         # Protocol classes (URLStore, Cache)
│   │   │   ├── dynamo.py            # DynamoDB implementation
│   │   │   └── cache.py             # Redis implementation (errors swallowed)
│   │   ├── shortcode/
│   │   │   └── generator.py         # Base62, secrets.choice, CSPRNG
│   │   └── validator/
│   │       └── url.py               # Scheme allow-list, SSRF blocklist, length cap
│
├── terraform/                       # ── Infrastructure ──────────────────
│   ├── modules/
│   │   ├── dynamodb/                # Table, GSI, TTL, encryption, PITR
│   │   ├── elasticache/             # Redis replication group, SG, TLS
│   │   ├── lambda/                  # Functions, IAM roles, VPC config
│   │   ├── api-gateway/             # REST API, routes, throttling, Lambda perms
│   │   ├── cloudfront-waf/          # Distribution, WAF rules, geo-block
│   │   └── monitoring/              # Dashboard, alarms, SNS topic
│   └── environments/
│       ├── dev/                     # Smallest sizing, full WAF
│       └── prod/                    # Multi-node Redis, PriceClass_All, tighter alarms
│
├── .github/workflows/
│   ├── ci.yml                       # PR: lint → type-check → test → tf validate → security scan
│   └── deploy.yml                   # Push to main: build → dev → smoke → prod (manual)
│
├── Makefile                         # Developer commands
├── ARCHITECTURE.md                  # Architecture Decision Records (ADRs)
└── README.md                        # ← you are here
```

---

## API Reference

### Authentication

| Endpoint | Auth | How                                                    |
|----------|------|--------------------------------------------------------|
| `POST /shorten` | ✅ Required | `x-api-key` header (API Gateway API key)               |
| `GET /{code}` | ❌ Public | No auth required anyone with the short link can use it |

API Gateway enforces the key, no valid key means `403 Forbidden`.

```bash
# Get your API key after deploying or can be found in AWS Console → API Gateway → API Keys
terraform -chdir=terraform/environments/dev output -raw api_key_value
```

### `POST /shorten`

Create a shortened URL. **Requires `x-api-key` header.**

```bash
curl -X POST https://<endpoint>/shorten \
  -H "Content-Type: application/json" \
  -H "x-api-key: <your-api-key>" \
  -d '{"url": "https://example.com/very/long/url"}'
```

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `url` | `HttpUrl` | ✅ | URL to shorten (http/https only) |
| `custom_code` | `string` (4–20 chars, `[a-zA-Z0-9-]`) | ❌ | Vanity short code |
| `expires_in_days` | `int` (1–3 650) | ❌ | Auto-expire after N days |

**Response `201 Created`:**

```json
{
  "code": "my-code",
  "short_url": "https://d123abc.cloudfront.net/my-code",
  "original_url": "https://example.com/very/long/url",
  "expires_at": "2026-05-16T10:30:00Z"
}
```

**Error responses:** `400` (validation), `409` (code conflict), `500` (internal).

---

### `GET /{code}`

Redirect to the original URL.

| Status | Meaning | Headers                                         |
|--------|---------|-------------------------------------------------|
| `301` | Redirect | `Location`, `Cache-Control: public, max-age=60` |
| `404` | Code not found | -                                               |
| `410` | Code expired | -                                               |

---

## Development

### Makefile Targets

| Target | Description |
|--------|-------------|
| `make install` | Install all Python dependencies via Poetry |
| `make lint` | Format check with black |
| `make format` | Auto-format with black |
| `make clean` | Remove build and dist directories |
| `make zip` | Build Lambda deployment zips (shorten.zip + redirect.zip) |
| `make apply ENV=dev` | Build zips, then `terraform init` + `apply` for the given environment |
| `make deploy ENV=dev` | Build zips, then push new code to Lambda via AWS CLI (`--publish`) |

### Tail Logs

```bash
aws logs tail /aws/lambda/url-shortener-shorten-dev --follow
aws logs tail /aws/lambda/url-shortener-redirect-dev --follow
```

---

## Environments

| Environment | Redis Nodes | Lambda Memory | WAF | Alarms | Price Class |
|-------------|-------------|---------------|-----|--------|-------------|
| **dev** | 1 × `cache.t4g.micro` | 256 MB | ✅ | ✅ (relaxed) | `PriceClass_100` |
| **prod** | 2 × `cache.r7g.large` | 1 024 MB | ✅ (full rules + geo-block) | ✅ (tight: 3 errors, 500 ms p99) | `PriceClass_All` |

---

## CI/CD Pipeline

```
PR opened
  └─► python-ci ─► zip-build ─► terraform-ci

Push to main
  └─► build ─► deploy-dev ─► smoke-test ─► deploy-prod (manual gate)
```

- **Authentication:** OIDC federation, no long-lived AWS keys.
- **Security gates:** `trivy config` + `checkov` must pass with zero HIGH/CRITICAL findings.
- **Prod deploy:** Requires manual approval in the GitHub `production` environment.

---

## Rollback

Every Lambda deploy publishes a new **immutable version**. The `live` alias points to the active version. Rollback instantly flips the alias no redeploy, no zip rebuild, no Terraform apply.

### How it works

```
Version 1 ─► Version 2 ─► Version 3 (current)
                               ▲
                          "live" alias ──── API Gateway invokes this

After rollback to version 2:

Version 1 ─► Version 2 ─► Version 3
                  ▲
             "live" alias ──── traffic instantly switches
```

### Manual rollback (CLI)

```bash
# 1. List available versions
aws lambda list-versions-by-function --function-name url-shortener-shorten-dev

# 2. Roll back by updating the alias to a previous version
aws lambda update-alias --function-name url-shortener-shorten-dev --name live --function-version 3
aws lambda update-alias --function-name url-shortener-redirect-dev --name live --function-version 3
```

### Manual rollback (GitHub Actions)

1. Go to **Actions → Rollback → Run workflow**
2. Select the environment (`dev` / `prod`)
3. Enter the version number
4. Click **Run workflow**

The workflow verifies the version exists, flips both aliases, confirms the switch, and runs a smoke test.

### Rollback scope

| What | How to roll back | Speed |
|------|-----------------|-------|
| **Lambda code** (bad handler logic) | `aws lambda update-alias` to previous version | **Instant** (~1 s) |
| **Environment variables** (wrong config) | Fix in `terraform.tfvars` → `terraform apply` | ~30 s |
| **Infrastructure** (wrong Terraform) | `git revert <sha>` → push to main → pipeline redeploys | ~5 min |
| **DynamoDB schema** | Restore from PITR (point-in-time recovery) | ~10 min |

### After rolling back

After an instant alias rollback, the `live` alias is out of sync with Terraform state (Terraform thinks it points to the latest version). To re-sync:

```bash
# Option A: Fix forward fix the code, push, let the pipeline deploy a new version
# Option B: Re-sync Terraform state to match the rolled-back alias
terraform -chdir=terraform/environments/<env> apply -refresh-only
```

---

## Key Design Decisions

> Full ADRs with context, alternatives considered, and consequences are in [`ARCHITECTURE.md`](ARCHITECTURE.md).

---

## Future Improvements

- **Authentication upgrade**: Replace API Gateway API keys with a proper auth mechanism:
  - **Amazon Cognito + JWT**: user pools with OAuth2/OIDC tokens, supports sign-up/login flows
  - **Lambda Authorizer**: custom token validation (e.g. validate JWTs from an external IdP like Auth0, Okta, or Keycloak)
  - **IAM authorization**: for service-to-service calls using SigV4 signed requests
- **Per-user URL management**: list, edit, delete URLs tied to an authenticated user
- **Analytics dashboard**: click-through rates, geographic distribution, referrer tracking
- **Custom domains**: bring-your-own short domain with ACM certificates
- **Rate limiting per user**: usage plans tied to authenticated identity, not just IP
- **URL preview / unfurling**: `GET /{code}+` returns metadata instead of redirecting
- **Bulk URL creation**: batch `POST /shorten` endpoint for importing many URLs at once
- **X-Ray tracing**: flip `enable_xray_tracing = true` in Terraform and re-add `Tracer` to handlers
- **Provisioned concurrency**: eliminate cold starts for prod redirect function
