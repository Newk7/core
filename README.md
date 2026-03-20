# core

Infrastructure, Python pipeline, and deployment for **District Solutions AI** (`districtsolutions.ai`).

## Services

| Service | Container | Port | Purpose |
|---------|-----------|------|---------|
| nginx | core-nginx | 80, 443 | TLS termination, reverse proxy, basic auth |
| Website | district-web | 80 (internal) | Company website SPA (districtsolutions.ai) |
| Open WebUI | biz-tool-oweb | 9322 → 8080 | AI chat / knowledge base (kbaas.districtsolutions.ai) |
| API | biz-tool-api | 8000 | FastAPI REST API for task pipeline + SOC + contact form |
| Worker | biz-tool-worker | — | SQS polling task processor |
| SOC Worker | soc-worker | — | LangGraph agent orchestration + scheduler |
| SOC Web | soc-web | 3001 → 3000 | AI-SOC dashboard (aisoc.districtsolutions.ai) |
| Postgres | biz-tool-postgres | 5432 | Task + SOC databases |
| fail2ban | (host-level) | — | Auto-ban brute force + bot scans |

## Architecture

```
Internet → DNS → EC2 (34.234.159.163) → nginx (TLS + auth) → services
                                                              ├─ districtsolutions.ai       → district-web (public)
                                                              ├─ kbaas.districtsolutions.ai  → Open WebUI (OWU JWT auth)
                                                              ├─ api.districtsolutions.ai    → FastAPI (basic auth)
                                                              ├─ aisoc.districtsolutions.ai  → soc-web + core API (basic auth)
                                                              └─ pg.districtsolutions.ai     → pgAdmin (basic auth)
```

- **Compute**: EC2 t3.medium (Amazon Linux 2023) with Docker
- **Images**: ECR (5 repos with scan-on-push, lifecycle keeps last 10)
- **Data**: S3 (task manifests + parquet) + Postgres (task + SOC databases)
- **Queue**: AWS SQS (task queue + result queue with DLQs)
- **API**: FastAPI/Uvicorn REST API
- **Workers**: SQS-polling task workers + LangGraph SOC agent worker
- **Security**: nginx TLS + rate limiting + basic auth + fail2ban

## Production Deployment (ECR)

Production images are stored in AWS ECR. The workflow is: **build → push → pull → restart**.

```bash
# First-time ECR setup (only once)
aws cloudformation deploy --template-file stack/cf/ecr/ecr.yaml \
    --stack-name core-ecr --parameter-overrides Environment=prod
aws cloudformation deploy --template-file stack/cf/ecr/ecr-policy.yaml \
    --stack-name core-ecr-policy --capabilities CAPABILITY_NAMED_IAM

# Build and push all images
./scripts/build-push-all.sh

# Build and push a single service
./scripts/build-push-api.sh

# Restart all services (pulls from ECR)
./scripts/restart-all.sh

# Restart a single service
./scripts/restart-api.sh

# Clean up old local images
./scripts/docker-prune.sh
```

### Making Changes

1. Edit code
2. Build and push: `./scripts/build-push-api.sh` (or whichever service changed)
3. Restart: `./scripts/restart-api.sh`

Or build+push all at once: `./scripts/build-push-all.sh` then `./scripts/restart-all.sh`

## Local Development

Local builds don't require ECR access. Images are built directly from source.

```bash
# 1. Configure
cp .env.example .env              # Fill in secrets

# 2. Create docker network
docker network create core-net

# 3. Build and start everything locally
./scripts/local/up.sh

# Or build individual services
./scripts/local/build-api.sh
./scripts/local/build-soc-worker.sh

# Or use restart-all.sh with --build flag
./scripts/restart-all.sh --build
```

For the SOC web frontend (lives in a separate repo), set `SOC_WEB_DIR` to point to the ai-soc web directory:

```bash
export SOC_WEB_DIR=/path/to/ai-soc/web
./scripts/local/build-soc-web.sh
```

## Project Structure

```
core/                             # Python package
  api/server.py                   # FastAPI endpoints (tasks, upload, contact, SOC routes)
  eng/                            # Shared resources, task dispatcher, worker loop
  jobs/                           # Task lifecycle model
  s3/                             # S3 upload/download
  sqs/                            # SQS publish/consume
  db/                             # Postgres connection pool (psycopg2)
  docling/                        # Document → markdown conversion
  shred/                          # Document shredding pipeline
  soc/                            # AI-SOC platform backend
    api/                          # SOC API router + sub-routers
    db/                           # SQLAlchemy models + session
    tools/                        # Security tool integrations (GuardDuty, Sentinel, Wiz, Qualys, Snyk)
    orchestrator/                 # LangGraph agents, graph, runner
    scripts/                      # Ingestion, sync, scheduler

stack/                            # Docker stack definitions
  {service}/                      # Dockerfile + docker-compose.yaml per service
  cf/                             # CloudFormation templates (EC2, S3, SQS, SES, ECR)
  nginx/                          # Nginx reverse proxy + SSL configs
  fail2ban/                       # fail2ban jails and filters

scripts/                          # Production deployment scripts
  common.sh                       # Shared ECR vars and helpers
  build-push-{service}.sh         # Build and push to ECR (api, worker, soc-worker, soc-web, district-web)
  build-push-all.sh               # Build and push all images
  restart-{service}.sh            # Pull from ECR and restart (api, worker, soc-worker, soc-web, district-web, db, oweb, nginx)
  restart-all.sh                  # Pull and restart all services in order
  docker-prune.sh                 # Clean up old Docker images
  local/                          # Local development scripts
    build-{service}.sh            # Build image locally (no ECR)
    build-all.sh                  # Build all images locally
    up.sh                         # Build and start everything locally

notes/                            # Architecture documentation
  01-getting-started.md           # Full setup guide
  02-architecture.md              # Network topology, ECR, security layers
  03-quick-reference.md           # Commands, URLs, API usage
```

## Documentation

| Doc | Content |
|-----|---------|
| [01-getting-started.md](notes/01-getting-started.md) | Full setup: AWS, DNS, SSL, Docker, fail2ban |
| [02-architecture.md](notes/02-architecture.md) | Network topology, ECR workflow, security layers, port map |
| [03-quick-reference.md](notes/03-quick-reference.md) | Commands, URLs, API usage, backups |

## AWS Account

- **Account**: 381492049589
- **Region**: us-east-1
- **ECR**: `381492049589.dkr.ecr.us-east-1.amazonaws.com/core/prod/*`

## Key Decisions

- **ECR for images** — custom images are built, pushed to ECR, then pulled on the server. Saves disk space vs local builds. ECR lifecycle keeps last 10 images per repo.
- **nginx basic auth on API** — protects API endpoints until go-live. `/health` is exempt.
- **No nginx auth on kbaas** — OpenWebUI uses JWT auth. Basic auth would break it.
- **gzip disabled on kbaas** — breaks Server-Sent Events for streaming chat.
- **fail2ban on host** — not in container. Reads nginx log files directly.
- **core-net Docker network** — all containers join for DNS-based service discovery.
- **SQS instead of Redis** — task queue and result notifications via AWS SQS with DLQs.
- **S3 for artifacts** — task manifests, parquet output stored in versioned S3 bucket.
- **Postgres 16 pinned** — avoids data directory compatibility issues.
- **API doesn't install SOC deps** — SOC routes are conditionally loaded via try/except. Keeps the API image smaller.
- **SOC deps are optional** — `pip install ".[soc]"` only in soc-worker. Isolates heavy langchain/langgraph from base image.
