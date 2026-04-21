# URL Shortener

> A serverless URL shortener on AWS built with **Python 3.13**, **Terraform**, **AWS Lambda**, and **DynamoDB** with github actions as cicd.

## Note On Scope

This solution is intentionally focused on clarity of infrastructure design, operational decisions, and follow-up technical discussion rather than full production hardening.

The assignment requested the application code in **Go, Node.js, TypeScript, or Ruby**. In this implementation, the Lambda handlers were written in **Python**. This was a deliberate tradeoff to keep the request/response logic small and easy to review, and to use the limited exercise time on the areas most central to the role:

- Terraform module structure
- AWS service composition
- CI/CD provisioning
- multi-environment handling
- monitoring and rollback
- WAF and malicious traffic controls

If this project were taken further, the most direct next step would be to port the Lambda handlers to **TypeScript** or **Go** while preserving the same infrastructure layout and operational model.

---

## Architecture

> Full rationale for every decision is recorded in [`ARCHITECTURE.md`](ARCHITECTURE.md).

| Layer | Service | Purpose                                                                        |
|-------|---------|--------------------------------------------------------------------------------|
| **Edge** | CloudFront | Global edge caching for 301 redirects, TLS termination                         |
| **Edge** | WAF | IP rate-limiting (2000 req / 5 min), geo-blocking, AWS managed rule sets       |
| **Compute** | API Gateway (REST) | Route `POST /shorten` and `GET /{code}` to Lambda                              |
| **Compute** | Lambda × 2 | Python on arm64, zip deployment                                                |
| **Data** | DynamoDB | Primary store for short codes, redirects, and TTL expiry                       |
| **Observe** | CloudWatch + SNS | Simple dashboard, Lambda error alarms, DynamoDB throttle alerts, email alerts |

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

## Setup From Scratch

Use this when you want to bring the project up in a fresh AWS account or add a new environment.

### 1. Clone and install dependencies

```bash
git clone <your-repo-url>
cd url-shortner
make install
```

### 2. Configure AWS locally

```bash
aws configure
aws sts get-caller-identity
```

### 3. Create the shared VPC first

This project expects the shared VPC in `terraform/vpc/` to exist before any environment is applied.

```bash
terraform -chdir=terraform/vpc init
terraform -chdir=terraform/vpc apply
```

### 4. Build the Lambda deployment packages

```bash
make zip
```

### 5. Prepare the target environment

Pick an existing environment like `dev` or `prod`, or copy one to create a new one.

```bash
cp -R terraform/environments/dev terraform/environments/<new-env>
```

Then update at least these files in `terraform/environments/<new-env>/`:

- `backend.tf`: use a unique S3 state key such as `<new-env>/terraform.tfstate`
- `variables.tf`: set the default `environment` if needed
- `terraform.tfvars`: set `environment`, `alarm_email`, `base_url`, and any environment-specific values
- `main.tf`: keep sizing and feature flags appropriate for the new environment

Important:

- `base_url` should be the public URL users should receive in responses
- use the CloudFront domain or a custom domain
- do not use the API Gateway `execute-api` hostname

### 6. Apply the environment

```bash
make apply ENV=<new-env>
```

### 7. Check the important outputs

```bash
terraform -chdir=terraform/environments/<new-env> output
```

For `dev`, also get the API key:

```bash
terraform -chdir=terraform/environments/dev output -raw api_key_value
```

### 8. Verify from the console

- Lambda: both functions exist and the `live` alias points to a version
- API Gateway: stage is deployed for the environment
- CloudFront: distribution is deployed and points to API Gateway
- DynamoDB: table exists
- CloudWatch: dashboard exists
- SNS: confirm the alarm email subscription if still pending

### 9. Optional: GitHub Actions OIDC for CI/CD

If this is a fresh AWS account, create the GitHub OIDC provider and deploy role before using the workflows.

```bash
terraform -chdir=terraform/bootstrap/github-actions init
terraform -chdir=terraform/bootstrap/github-actions apply
```

Then add the role ARN to the GitHub repository variable:

- `AWS_DEPLOY_ROLE_ARN`

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
│   │   ├── elasticache/             # Redis module kept for future use
│   │   ├── lambda/                  # Functions, IAM roles, VPC config
│   │   ├── api-gateway/             # REST API, routes, throttling, Lambda perms
│   │   ├── cloudfront-waf/          # Distribution, WAF rules, geo-block
│   │   └── monitoring/              # Dashboard, alarms, SNS topic
│   └── environments/
│       ├── dev/                     # Smallest sizing, basic alarms, DynamoDB-only app path
│       └── prod/                    # Full WAF, tighter alarms, DynamoDB-only app path
│
├── .github/workflows/
│   ├── ci.yml                       # PR: lint → type-check → zip build → terraform fmt → security scan
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

| Environment | Lambda Memory | WAF | Alarms | Price Class | Notes |
|-------------|---------------|-----|--------|-------------|-------|
| **dev** | 256 MB | ✅ | ✅ (errors + DynamoDB throttles) | `PriceClass_100` | Simple monitoring, no latency alarm |
| **prod** | 1 024 MB | ✅ (rate-limit + AWS managed rules + geo-block) | ✅ (errors + 500 ms p99 + DynamoDB throttles) | `PriceClass_All` | Tighter alerts for higher traffic |

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

## Monitoring

- **Dev:** CloudWatch dashboard, Lambda error alarms, DynamoDB throttle alarm, SNS email notifications
- **Prod:** Same baseline alerts plus Lambda p99 latency alarms and full WAF managed rules
- **Console check:** CloudWatch → Dashboards → `url-shortener-dev`
- **Alarm email:** confirm the SNS subscription email once after the first `terraform apply`

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
- **Richer monitoring**: add latency alarms in dev only if traffic justifies the noise, and add business metrics such as URLs created / redirect count
- **Custom domains**: bring-your-own short domain with ACM certificates
- **Rate limiting per user**: usage plans tied to authenticated identity, not just IP
- **URL preview / unfurling**: `GET /{code}+` returns metadata instead of redirecting
- **Bulk URL creation**: batch `POST /shorten` endpoint for importing many URLs at once
- **X-Ray tracing**: flip `enable_xray_tracing = true` in Terraform and re-add `Tracer` to handlers
- **Provisioned concurrency**: eliminate cold starts for prod redirect function
- **Redis hot-path cache**: reintroduce Redis only when DynamoDB read latency or cost becomes a real bottleneck
