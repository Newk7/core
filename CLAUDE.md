# Core — Claude Code Guidelines

## Project Overview

This is the **core** monorepo for District Solutions AI infrastructure. It contains:
- A FastAPI REST API (`core/api/`)
- A SQS-based task worker for document processing (`core/eng/`)
- An AI-SOC security platform backend (`core/soc/`)
- Docker stack definitions for all services (`stack/`)
- CloudFormation templates for AWS resources (`stack/cf/`)
- Deployment and operational scripts (`scripts/`)

Production runs on a single EC2 instance with Docker Compose, nginx reverse proxy, and all services on a shared `core-net` Docker network.

## Architecture Rules

- **Single EC2 host** — all containers run on one machine via Docker Compose. No Kubernetes, no ECS.
- **ECR for images** — custom images are built, pushed to ECR, then pulled on the server. Never store large images locally long-term. See `scripts/build-push-*.sh`.
- **SQS for async work** — tasks are dispatched via SQS, not background threads or Celery. The worker long-polls SQS.
- **Postgres for state** — core app uses one shared Postgres container (`biz-tool-postgres`) with `biztool` and `socagent` databases. Independent services (Mattermost, Gitea) get their own dedicated Postgres containers for isolation.
- **S3 for artifacts** — task results, manifests, and parquet files go to S3. Never store large files in Postgres.
- **nginx handles TLS, auth, and routing** — services expose internal ports only. nginx terminates SSL and applies basic auth where needed.

## Python Conventions

- **Python 3.11** across all services. Do not use 3.12+ features.
- **Dependencies in `pyproject.toml`** — base deps for api/worker, `[soc]` optional group for SOC-specific deps (langchain, langgraph, etc).
- **The API must work without SOC deps** — `core/api/server.py` conditionally imports SOC routes with try/except. Never add SOC imports to non-SOC code paths.
- **Use `core.log`** — all modules use `from core.log import log`. No `print()` or custom logger setup.
- **Pydantic for request/response models** — defined in the endpoint files, not in separate model files.
- **psycopg2-binary for DB** — the api and worker use `core.db` (raw psycopg2 connection pool). SOC uses SQLAlchemy (`core.soc.db`).
- **boto3 for AWS** — S3, SQS, SES all via boto3 using the EC2 IAM role. No hardcoded AWS credentials.

## SOC Module Conventions

- **SOC code lives in `core/soc/`** — it is part of this repo, not a separate package.
- **LangGraph for agent orchestration** — supervisor pattern with triage_agent, vuln_agent, hunt_agent.
- **Claude Sonnet via langchain-anthropic** — all agents use `ChatAnthropic`. Do not use the Anthropic SDK directly in SOC code.
- **SQLAlchemy for SOC database** — `core/soc/db/models.py` defines the ORM. `core/soc/db/session.py` manages sessions.
- **HITL uses in-process MemorySaver** — the soc-worker must be a single process for thread state. Do not split across workers.
- **Tool modules are self-contained** — each file in `core/soc/tools/` wraps one external API (GuardDuty, Sentinel, Wiz, Qualys, Snyk). Each exports LangChain tool functions.

## Docker & Deployment Conventions

- **One Dockerfile per service** in `stack/{service}/Dockerfile`.
- **One docker-compose.yaml per service** in `stack/{service}/`. Each references the ECR image with a local `build:` fallback.
- **Environment variables** — secrets come from `/opt/ds/env.sh` on the server (sourced before running scripts). Locally, use `.env` file. Never hardcode secrets.
- **ECR image tags** — tagged with git short SHA + `latest`. Lifecycle policy keeps last 10 images per repo.
- **Scripts use `scripts/common.sh`** — all build/restart scripts source this for shared ECR vars and helpers. Keep new scripts consistent with this pattern.
- **Restart scripts pull from ECR** — `restart-{service}.sh` does `docker compose pull` then `up -d`. Use `--build` flag only for local fallback.
- **Local dev scripts in `scripts/local/`** — these build locally without ECR. Use for development.
- **Cross-platform builds** — `build-push-*.sh` scripts use `--platform linux/amd64` (set via `BUILD_PLATFORM` in `common.sh`) so images built on ARM Macs run on the x86 EC2 server.

## Code vs Image Iteration

Python services (api, worker, soc-worker) mount the host `core/` directory as a volume (`${CORE_DIR}/core:/app/core:ro`). This means:

- **Python code changes** → `git pull` + restart the container. No rebuild needed.
- **Dependency changes** (`pyproject.toml`) → rebuild the image and push to ECR, then restart.
- **Dockerfile changes** → rebuild the image and push to ECR, then restart.

On the server:
```bash
# Code-only change (fast):
cd /opt/ds/core && git pull
./scripts/restart-api.sh

# Dependency change (rebuild required):
./scripts/build-push-api.sh    # builds + pushes to ECR
./scripts/restart-api.sh       # pulls new image + restarts
```

The Dockerfiles use a two-layer pattern: deps are installed first from `pyproject.toml` (cached), then code is copied. Even when rebuilding, unchanged deps are cached.

## File Organization

```
core/                    # Python package
  api/                   # FastAPI app
    server.py            # Main app, routes, models
  db/                    # Postgres connection pool (psycopg2)
  eng/                   # Shared resources, task dispatcher, worker loop
  jobs/                  # Task lifecycle handlers
  s3/                    # S3 upload/download
  sqs/                   # SQS publish/consume
  shred/                 # Document shredding pipeline
  docling/               # Document-to-markdown conversion
  soc/                   # AI-SOC platform
    api/                 # SOC API router + sub-routers
    db/                  # SQLAlchemy models + session
    tools/               # Security tool integrations (one file per tool)
    orchestrator/        # LangGraph agents, graph, runner
    scripts/             # Ingestion, sync, scheduler
stack/                   # Docker stack definitions
  {service}/             # Dockerfile + docker-compose.yaml per service
  cf/                    # CloudFormation templates
  nginx/                 # Nginx config files
scripts/                 # Deployment scripts (build-push, restart, infra)
  local/                 # Local development build scripts
notes/                   # Architecture docs
```

## Things to Never Do

- Do not add dependencies to the base `[project.dependencies]` that are only needed by SOC. Use `[project.optional-dependencies.soc]`.
- Do not hardcode paths like `/opt/ds/...` in Python code. Use environment variables.
- Do not add databases to `biz-tool-postgres`. Core app uses `biztool` and `socagent` only. New services get their own dedicated Postgres container (see `stack/gitea/` or `stack/mattermost/` for the pattern).
- Do not expose container ports to the host unless absolutely necessary. Services communicate via `core-net`.
- Do not modify nginx configs without understanding the fail2ban integration — auth failure logs are parsed by fail2ban jails.
- Do not use `docker compose up --build` in production scripts. Always pull from ECR.
- Do not add Python type stubs, docstring-only changes, or formatting-only changes to files you aren't modifying for functional reasons.
- Do not add a new subdomain without following the full checklist in `notes/02-architecture.md` § "Adding a New Subdomain / Service" — DNS, SSL cert, nginx config, docker-compose, env vars, restart script, and documentation updates.
