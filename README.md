# core

Infrastructure, Python pipeline, and deployment for **District Solutions AI** (`districtsolutions.ai`).

## Services

| Service | Container | Port | Purpose |
|---------|-----------|------|---------|
| nginx | core-nginx | 80, 443 | TLS termination, reverse proxy, basic auth |
| Website | district-web | 80 (internal) | Company website SPA (districtsolutions.ai) |
| Open WebUI | biz-tool-oweb | 9322 → 8080 | AI chat / knowledge base (kb.districtsolutions.ai) |
| API | biz-tool-api | 8000 | FastAPI REST API for task pipeline + contact form |
| Worker | biz-tool-worker | — | SQS polling task processor |
| Postgres | biz-tool-postgres | 5432 | Task tracking database |
| fail2ban | (host-level) | — | Auto-ban brute force + bot scans |

## Architecture

```
Internet → DNS → EC2 (34.234.159.163) → nginx (TLS + auth) → services
                                                              ├─ districtsolutions.ai     → district-web container (public)
                                                              ├─ kb.districtsolutions.ai  → Open WebUI (OWU JWT auth)
                                                              └─ api.districtsolutions.ai → FastAPI (basic auth)
```

- **Compute**: EC2 t3.medium (Amazon Linux 2023) with Docker
- **Data Layer**: S3 (task manifests + parquet) + Postgres (task tracking)
- **Message Queue**: AWS SQS (task queue + result queue with DLQs)
- **API**: FastAPI/Uvicorn REST API
- **Workers**: SQS-polling task workers for document processing
- **UI**: Open WebUI behind nginx reverse proxy
- **Security**: nginx TLS + rate limiting + basic auth + fail2ban

### Task Flow

1. Client submits task via REST API (`POST /api/v1/tasks` or `/api/v1/upload`)
2. API creates task in Postgres, publishes to SQS task queue
3. Worker polls SQS, deserializes task, runs handler (shred, chat, etc.)
4. Worker converts documents to markdown via Docling, writes parquet to S3
5. Results uploaded to S3 at `tasks/{uuid}/manifest.json`
6. Completion notification sent to SQS result queue
7. Task status updated in Postgres

## Project Structure

```
core/                             # Python package
  log.py                          # Logger (stdout with color)
  api/server.py                   # FastAPI endpoints (tasks, upload, contact form)
  eng/resources.py                # Shared DB, SQS, S3 clients
  eng/handle_task.py              # Task dispatcher
  eng/worker.py                   # SQS polling worker loop
  jobs/task.py                    # Task lifecycle model
  s3/                             # S3 upload/download
  sqs/                            # SQS publish/consume
  db/get_db_pool.py               # Postgres connection pool
  docling/                        # Document → markdown conversion
  shred/run_shred.py              # Document shredding pipeline

stack/                            # Docker + infrastructure
  nginx/                          # Nginx reverse proxy + SSL
    nginx.conf                    # Main config (TLS, rate limiting, security headers)
    conf.d/                       # Virtual hosts (districtsolutions.ai, kb, api)
    nginx.yaml                    # Docker compose
  district-web/                   # Company website container (compose only, builds from frontend repo)
  api/                            # API container (Dockerfile + compose)
  worker/                         # Worker container (Dockerfile + compose)
  db/                             # Postgres (compose + schema)
  oweb/                           # Open WebUI (compose)
  fail2ban/                       # fail2ban jails and filters
  cf/                             # CloudFormation templates
    build-host/host.yaml          # EC2 instance
    s3/s3.yaml                    # Task data bucket
    sqs/sqs.yaml                  # Task + result queues
    ses/ses.yaml                  # SES email identity + DKIM + IAM policy

scripts/                          # Deployment scripts
  restart-all.sh                  # Start all services in order
  restart-nginx.sh                # Quick nginx restart
  generate-htpasswd.sh            # Create basic auth credentials
  setup-fail2ban.sh               # Install + configure fail2ban

notes/                            # Documentation
  01-getting-started.md           # Full setup guide
  02-architecture.md              # Network topology + security layers
  03-quick-reference.md           # Commands, URLs, API usage
  openapi-tool-servers.md         # OpenAPI tool servers for OpenWebUI
```

## Quick Start

```bash
# 1. Configure
cp .env.example .env              # Fill in secrets

# 2. Place SSL cert
mkdir -p data/ssl
# Copy districtsolutions.ai.crt and .key into data/ssl/

# 3. Create docker network + htpasswd
docker network create core-net
./scripts/generate-htpasswd.sh

# 4. Start everything
./scripts/restart-all.sh
```

See [notes/01-getting-started.md](notes/01-getting-started.md) for the full step-by-step guide.

## Documentation

| Doc | Content |
|-----|---------|
| [01-getting-started.md](notes/01-getting-started.md) | Full setup: AWS, DNS, SSL, Docker, fail2ban |
| [02-architecture.md](notes/02-architecture.md) | Network topology, security layers, port map |
| [03-quick-reference.md](notes/03-quick-reference.md) | Commands, URLs, API usage, backups |
| [openapi-tool-servers.md](notes/openapi-tool-servers.md) | OpenAPI tool servers for OpenWebUI |

## Python Package (`core/`)

```python
from core.log import create_log
from core.jobs.task import Task
from core.eng.resources import EngResources
from core.sqs.publish import publish_task

# Create and queue a task
tk = Task(type='shred', msg='process document', user_id='user1')
tk.insert(db_pool)
publish_task(task_data=tk.to_dict())

# Status codes: -999=init, 0=success, 150-500=processing, <0=error
```

## AWS Account

- **Account**: 381492049589
- **Region**: us-east-1
- **VPC**: vpc-0dd28884da7e4d4eb (10.0.0.0/16)
- **Subnet**: subnet-0531a7a14eef69db2 (10.0.0.0/24, us-east-1b, public)

## Key Decisions

- **Purchased SSL cert** — not Let's Encrypt. Cert files in `data/ssl/`, referenced by nginx. Renewal is manual when cert expires.
- **nginx basic auth on API** — protects API endpoints until go-live. `/health` is exempt. Remove `auth_basic` lines when ready.
- **No nginx auth on kb subdomain** — OWU uses JWT in the Authorization header. Adding basic auth would intercept those tokens and break OWU.
- **gzip disabled on kb subdomain** — breaks Server-Sent Events for streaming chat responses.
- **fail2ban on host** — not in container. Uses `backend = auto` to read log files directly.
- **core-net Docker network** — all containers join this external network for DNS-based service discovery.
- **SQS instead of Redis** — task queue and result notifications via AWS SQS with DLQs for reliability.
- **S3 for artifacts** — task manifests, parquet output, and bbox artifacts stored in versioned S3 bucket.
- **Postgres 16 pinned** — avoids data directory compatibility issues with newer versions.
- **Default nginx server** — drops connections with unknown Host headers (returns 444) to reject port scanners.
