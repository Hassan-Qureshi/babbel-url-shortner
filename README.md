# URL Shortener

> A serverless URL shortener on AWS built with **Python 3.13**, **Terraform**, **AWS Lambda**, and **DynamoDB** with github actions as cicd.

---

## Architecture

> Full rationale for every decision is recorded in [`ARCHITECTURE.md`](ARCHITECTURE.md).

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
# Step 0 — one-time VPC setup (shared across all environments)
cd terraform/vpc
terraform init && terraform apply
```

---

## Project Structure

```
url-shortner/
│
├── terraform/                       # ── Infrastructure ──────────────────
│   ├── vpc/                         # Shared VPC — apply once before environments
│   │   ├── main.tf                  # VPC, 2 public + 2 private subnets, IGW, NAT GW
│   │   └── outputs.tf               # vpc_id, private_subnet_ids (read via remote state)
├── ARCHITECTURE.md                  # Architecture Decision Records (ADRs)
└── README.md                        # ← you are here
```

---

## Key Design Decisions

> Full ADRs with context, alternatives considered, and consequences are in [`ARCHITECTURE.md`](ARCHITECTURE.md).
---