# District Solutions AI - Architecture

## Network Topology

```
                          INTERNET
                             │
                     ┌───────┴───────┐
                     │  DNS Provider │
                     │  (A records)  │
                     └───────┬───────┘
                             │
                     34.234.159.163 (Elastic IP)
                             │
                     ┌───────┴───────┐
                     │  AWS EC2      │
                     │  SG: 22 CIDR  │
                     │  80,443 open  │
                     │  5432 CIDR    │
                     └───────┬───────┘
                             │
                ┌────────────┴────────────┐
                │     Docker Engine       │
                │     core-net network    │
                └────────────┬────────────┘
                             │
    ┌──────────────────┬─────┼─────┬──────────────────┬──────────────────┐
    │                  │     │     │                  │                  │
    ▼                  ▼     │     ▼                  ▼                  ▼
┌─────────┐    ┌──────────┐ │ ┌──────────┐    ┌──────────┐     ┌──────────────┐
│  nginx  │───▶│open-webui│ │ │   api    │───▶│  worker  │     │   postgres   │
│ :80/:443│    │  :8080   │ │ │  :8000   │    │(no port) │     │    :5432     │
│SSL+auth │    └──────────┘ │ └────┬─────┘    └────┬─────┘     │ biztool DB   │
└────┬────┘                 │      │               │           │ socagent DB  │
     │                      │      │               │           └──────────────┘
     │     ┌──────────┐     │      │               │
     ├────▶│ soc-web  │     │      │               │           ┌──────────────┐
     │     │  :3000   │     │      │               ├──────────▶│  AWS SQS     │
     │     └──────────┘     │      │               │           │  task queue  │
     │                      │      │               │           │  result queue│
     │     ┌──────────┐     │      │          ┌────┴─────┐     └──────────────┘
     ├────▶│ pg-admin │     │      │          │soc-worker│
     │     │   :80    │     │      │          │(no port) │     ┌──────────────┐
     │     └──────────┘     │      │          └──────────┘     │  AWS S3      │
     │                      │      │                           │  task data   │
     └────▶┌──────────┐    │      └──────────────────────────▶│  manifests   │
           │district- │    │                                   └──────────────┘
           │  web :80 │    │
           └──────────┘    │
                           │
                     ┌─────┴──────┐
                     │  fail2ban  │
                     │(host-level)│
                     └────────────┘
```

## Subdomain Routing

| URL | Nginx Auth | Backend | Purpose |
|-----|-----------|---------|---------|
| `https://districtsolutions.ai` | None (public) | district-web:80 | Company website (React SPA) |
| `https://kbaas.districtsolutions.ai` | None (OWU JWT) | biz-tool-oweb:8080 | AI chat / knowledge base |
| `https://api.districtsolutions.ai` | Basic auth | biz-tool-api:8000 | REST API for tasks + contact form |
| `https://pg.districtsolutions.ai` | Basic auth + pgAdmin login | pg-admin:80 | pgAdmin4 database UI |
| `https://aisoc.districtsolutions.ai` `/` | Basic auth | soc-web:3000 | AI-SOC dashboard (Next.js) |
| `https://aisoc.districtsolutions.ai` `/api/v1/soc/*` | Basic auth | biz-tool-api:8000 | SOC API routes on core API |
| `https://msg.districtsolutions.ai` | None (MM login) | core-mattermost:8065 | Mattermost messaging |
| `https://git.districtsolutions.ai` | Basic auth | gitea:8080 | Gitea self-hosted git server |

## Containers

| Container | Image | Port | Purpose |
|-----------|-------|------|---------|
| `core-nginx` | nginx:alpine | 80, 443 | TLS termination, reverse proxy, basic auth, rate limiting |
| `biz-tool-api` | core API (Python 3.11) | 8000 | FastAPI — task API + SOC API routes at `/api/v1/soc/` |
| `biz-tool-worker` | core worker (Python 3.11) | — | SQS consumer — document processing (shred, chat) |
| `soc-worker` | SOC worker (Python 3.11) | — | LangGraph orchestration + APScheduler + SQS consumer for SOC tasks |
| `soc-web` | Next.js (Node 20) | 3001→3000 | AI-SOC dashboard frontend |
| `biz-tool-oweb` | ghcr.io/open-webui | 9322→8080 | OpenWebUI — AI chat and knowledge base |
| `core-pipelines` | ghcr.io/open-webui/pipelines | 9099 | OpenWebUI custom pipelines |
| `biz-tool-postgres` | postgres:16-alpine | 5432 | PostgreSQL — `biztool` DB (tasks) + `socagent` DB (SOC) |
| `pg-admin` | dpage/pgadmin4 | — | pgAdmin4 web UI |
| `district-web` | React SPA in nginx | — | Company website |
| `core-mattermost` | mattermost-team-edition | 8065, 8443 | Mattermost messaging platform |
| `mattermost-pg` | postgres:17-alpine | — | Dedicated Mattermost database |
| `gitea` | gitea/gitea | 8080, 2222 | Self-hosted git server |
| `gitea-pg` | postgres:17-alpine | — | Dedicated Gitea database |
| `gitea-redis` | redis | — | Gitea caching / sessions |

## Databases

Services that need their own database get a **dedicated postgres container** for isolation. Only tightly-coupled services share a postgres instance.

### biz-tool-postgres (postgres:16-alpine)

Shared by `biz-tool-api`, `biz-tool-worker`, `soc-worker`. Contains:

**biztool** — core task system

| Table | Purpose |
|-------|---------|
| `tasks` | Task queue metadata (uuid, type, status, timestamps) |

**socagent** — AI-SOC platform

| Table | Purpose |
|-------|---------|
| `alerts` | Ingested security alerts from GuardDuty/Sentinel/Wiz |
| `investigations` | AI agent investigation results + HITL status |
| `assets` | Asset registry (hosts, IPs, criticality, FP patterns) |
| `analyst_feedback` | Human analyst decisions for accuracy tracking |

### mattermost-pg (postgres:17-alpine)

Dedicated postgres for Mattermost. Data at `data/mattermost/db/`.

### gitea-pg (postgres:17-alpine)

Dedicated postgres for Gitea. Data at `data/gitea/db/`.

---

## Core Task Architecture (SQS)

```
┌──────────┐    POST /api/v1/tasks    ┌───────────────────────┐
│  Client  │ ────────────────────────▶│  biz-tool-api         │
│ (SPA /   │                          │  (FastAPI on :8000)   │
│  webui)  │                          └───────────┬───────────┘
└──────────┘                                      │
                                         publish_task()
                                                  │
                                    ┌─────────────▼──────────────┐
                                    │  SQS: biz-tool-prod-       │
                                    │        task-queue           │
                                    │  (long-poll 20s, DLQ)      │
                                    └─────────────┬──────────────┘
                                                  │
                                         receive_messages()
                                                  │
                                    ┌─────────────▼──────────────┐
                                    │  biz-tool-worker           │
                                    │  handle_task() dispatch:   │
                                    │    shred → run_shred()     │
                                    │    chat  → (placeholder)   │
                                    └─────────────┬──────────────┘
                                                  │
                                        pub_update() + pub_manifest()
                                                  │
                              ┌────────────────────┼────────────────────┐
                              ▼                    ▼                    ▼
                    ┌──────────────┐    ┌──────────────┐    ┌──────────────┐
                    │  SQS result  │    │  Postgres    │    │  S3 bucket   │
                    │  queue       │    │  tasks table │    │  manifest +  │
                    └──────────────┘    └──────────────┘    │  parquet     │
                                                            └──────────────┘
```

**Flow:**
1. Client creates a Task via `POST /api/v1/tasks` or `/api/v1/upload`
2. API inserts task into Postgres, publishes JSON to SQS task queue
3. Worker long-polls SQS, deserializes Task, runs handler (shred, chat, etc.)
4. Worker converts documents to markdown via Docling, writes parquet to S3
5. Results uploaded to S3 at `tasks/{uuid}/manifest.json`
6. Completion notification sent to SQS result queue
7. Task status updated in Postgres

---

## AI-SOC Architecture

### Overview

The AI-SOC platform provides automated security alert triage, investigation, and threat hunting using LangGraph multi-agent orchestration. It is split across two repos:

- **core** (`/opt/ds/core`) — Backend: API routes, orchestrator, tools, worker, database schema
- **ai-soc** (`/opt/ds/ai-soc`) — Frontend: Next.js dashboard only

### Data Flow

```
                    ┌─────────────────────────────────────────────────┐
                    │       aisoc.districtsolutions.ai (nginx)        │
                    │  /            → soc-web:3000  (Next.js)         │
                    │  /api/v1/soc/ → biz-tool-api:8000 (core API)   │
                    │  /health      → biz-tool-api:8000 (no auth)    │
                    └──────────────────────┬──────────────────────────┘
                                           │
              ┌────────────────────────────┼────────────────────────────┐
              │                            │                            │
              ▼                            ▼                            ▼
    ┌──────────────────┐     ┌──────────────────────┐    ┌──────────────────┐
    │    soc-web        │     │    biz-tool-api       │    │    soc-worker     │
    │    (Next.js)      │     │    (FastAPI)           │    │    (Python)       │
    │                   │     │                        │    │                   │
    │  Dashboard        │     │  /api/v1/soc/alerts    │    │  APScheduler:     │
    │  Alerts           │     │  /api/v1/soc/invest..  │    │   ingest  (10m)   │
    │  Investigations   │     │  /api/v1/soc/assets    │    │   triage  (15m)   │
    │  Review Queue     │     │  /api/v1/soc/feedback  │    │   sync    (6h)    │
    │  Assets           │     │  /api/v1/soc/agent/*   │    │   hunt    (Mon)   │
    │  Investigate      │     │  /api/v1/soc/stats     │    │                   │
    │                   │     │                        │    │  SQS consumer:    │
    │  API client:      │     │  Manual triggers:      │    │   soc.investigate │
    │  /api/v1/soc/*    │────▶│  agent/* → SQS publish │───▶│   soc.hunt        │
    │  (relative paths, │     │                        │    │   soc.ingest      │
    │   nginx proxies)  │     └───────────┬────────────┘    │   soc.sync        │
    └──────────────────┘                  │                 └─────────┬─────────┘
                                          │                           │
                                          ▼                           ▼
                              ┌──────────────────┐       ┌──────────────────────┐
                              │   socagent DB    │       │   LangGraph          │
                              │   (Postgres)     │       │   Supervisor         │
                              │                  │       │                      │
                              │  alerts          │◀──────│  ┌────────────────┐  │
                              │  investigations  │       │  │ triage_agent   │  │
                              │  assets          │       │  │ (GuardDuty +   │  │
                              │  analyst_feedback│       │  │  Sentinel)     │  │
                              └──────────────────┘       │  ├────────────────┤  │
                                                         │  │ vuln_agent     │  │
                              ┌──────────────────┐       │  │ (Wiz + Qualys  │  │
                              │   S3 bucket      │◀──────│  │  + Snyk)       │  │
                              │   manifests      │       │  ├────────────────┤  │
                              └──────────────────┘       │  │ hunt_agent     │  │
                                                         │  │ (GuardDuty +   │  │
                                                         │  │  Sentinel +    │  │
                                                         │  │  Wiz)          │  │
                                                         │  └────────────────┘  │
                                                         └──────────────────────┘
```

### LangGraph Agents

| Agent | Tools | Responsibility |
|-------|-------|----------------|
| `triage_agent` | GuardDuty + Sentinel | Active threat detection, log timeline, IOC correlation |
| `vuln_agent` | Wiz + Qualys + Snyk | Exposure context, unpatched CVEs, attack paths |
| `hunt_agent` | GuardDuty + Sentinel + Wiz | Proactive weekly threat hunting |

All agents use Claude Sonnet 4.6 via LangChain. The supervisor routes work to agents and synthesizes a final verdict with severity + recommended actions.

### Security Tool Integrations

| Tool | Module | Capabilities |
|------|--------|-------------|
| AWS GuardDuty | `core/soc/tools/guardduty.py` | List findings, get finding details, get statistics |
| Microsoft Sentinel | `core/soc/tools/sentinel.py` | Query incidents, run KQL log queries, list alert rules |
| Wiz | `core/soc/tools/wiz.py` | Query issues, get resource details, list vulnerabilities (GraphQL) |
| Qualys | `core/soc/tools/qualys.py` | List host detections, get vulnerability details |
| Snyk | `core/soc/tools/snyk.py` | List project issues, get issue details |

### Human-in-the-Loop (HITL)

When the supervisor assesses **critical** or **high** severity, the investigation is flagged `hitl_status=pending` and appears in the **Review Queue** page. An analyst can:

- **Approve** — confirm the agent verdict, resume the LangGraph graph with analyst confirmation
- **Reject** — close with notes (analyst disagrees)
- **False positive** — close and automatically append analyst's notes as a false-positive pattern on the asset
- **Escalate** — override to critical regardless of agent assessment
- **Override severity** — correct the agent's severity without changing the action

All analyst decisions are recorded in `analyst_feedback` and shown in the dashboard accuracy metrics.

HITL thread state uses in-process `MemorySaver`. The orchestration must run in a single process (soc-worker), not split across workers.

### SOC Scheduled Jobs

| Job | Interval | Action |
|-----|----------|--------|
| Alert ingestion | Every 10 minutes | Pull new alerts from GuardDuty, Sentinel, Wiz |
| Auto-triage | Every 15 minutes | Investigate all `status=new` alerts via LangGraph |
| Asset sync | Every 6 hours | Sync asset registry from Wiz, AWS, Qualys |
| Threat hunt | Monday 8:00 AM | Proactive threat hunting across all sources |

### Manual Triggers

The dashboard can trigger actions on-demand via `POST /api/v1/soc/agent/*`:

| Endpoint | SQS Task Type | Action |
|----------|--------------|--------|
| `/agent/investigate` | `soc.investigate` | Run investigation with custom prompt |
| `/agent/hunt` | `soc.hunt` | Trigger threat hunt |
| `/agent/ingest` | `soc.ingest` | Trigger alert ingestion |
| `/agent/sync-assets` | `soc.sync` | Trigger asset sync |

These publish to the existing SQS task queue. The soc-worker consumes them alongside scheduled jobs via a background thread.

### Frontend Pages

| Page | URL | What you can do |
|------|-----|-----------------|
| Dashboard | `/` | Metrics, review queue banner, recent investigations, agent accuracy, quick actions |
| Review Queue | `/review` | Approve / reject / FP all pending HITL investigations |
| Alerts | `/alerts` | Filter/browse raw alerts, manually close or mark FP |
| Investigations | `/investigations` | Full investigation history |
| Investigation detail | `/investigations/:id` | Per-agent findings tabs, analyst resolution details, agent trace |
| Assets | `/assets` | Add/edit/delete assets, set criticality+owner, manage FP patterns inline |
| Investigate | `/investigate` | Run an ad-hoc investigation prompt |

---

## S3 Storage Layout

Bucket: `biz-tool-{env}-task-data-{account-id}`

```
tasks/{task-uuid}/
  ├── manifest.json              # Complete task state (JSON)
  ├── input/
  │   └── {filename}             # Uploaded input files
  ├── shred_results.parquet      # Output from shred pipeline
  └── artifacts/
      └── {bbox-file}.json       # Bounding box extraction from Docling
```

SOC investigation reports are also stored as manifests at `tasks/{task-id}/manifest.json` containing the full verdict, findings, and agent trace.

---

## AWS Infrastructure

| Service | Resource | Purpose |
|---------|----------|---------|
| EC2 | t3.medium, Amazon Linux 2023 | Docker host for all containers |
| S3 | `biz-tool-prod-task-data-381492049589` | Task data, manifests, investigation reports |
| SQS | `biz-tool-prod-task-queue` | Task dispatch (visibility: 300s, DLQ after 3 retries) |
| SQS | `biz-tool-prod-result-queue` | Completion notifications (visibility: 60s) |
| SES | `districtsolutions.ai` | Transactional email (DKIM, TLS required) |
| ECR | `core/prod/{api,worker,soc-worker,soc-web,district-web}` | Docker image registry |

### CloudFormation Stacks

| Template | Purpose |
|----------|---------|
| `stack/cf/build-host/host.yaml` | EC2 instance, security group, instance profile |
| `stack/cf/s3/s3.yaml` | S3 bucket with versioning and lifecycle |
| `stack/cf/sqs/sqs.yaml` | SQS queues + dead letter queues |
| `stack/cf/ses/ses.yaml` | SES domain identity + DKIM |
| `stack/cf/ecr/ecr.yaml` | ECR repositories (5 repos, scan-on-push, keep 10 images) |
| `stack/cf/ecr/ecr-policy.yaml` | IAM policy for ECR push/pull on ec2-ssm-role |

---

## Security Layers

```
Internet ──▶ DNS ──▶ EC2 Security Group ──▶ nginx ──▶ Service
                          │                    │
                     80/443 open to            ├─ TLS 1.2/1.3 (Let's Encrypt cert, auto-renewed)
                     0.0.0.0/0                 ├─ basic auth (API, pgAdmin, aisoc)
                     22 CIDR-locked            ├─ rate limiting (10r/s general, 5r/s auth)
                     5432 CIDR-locked          ├─ security headers
                                               ├─ default server drops unknown hosts
                                               │
                                           fail2ban
                                        (bans auth fails + bot scans + rate violations)
```

1. **EC2 Security Group** — Ports 80/443 open to `0.0.0.0/0` (required for Let's Encrypt + public site). SSH (22) CIDR-locked. Postgres (5432) CIDR-locked via `PostgresCIDR`/`PostgresCIDR1` parameters in `host.yaml`.
2. **nginx default server** — Drops connections with no matching Host header (returns 444)
3. **nginx TLS** — TLSv1.2/1.3 with strong ECDHE ciphers, Let's Encrypt cert (auto-renewed via cron)
4. **nginx rate limiting** — 10 req/s general, 5 req/s on auth endpoints
5. **nginx security headers** — `X-Content-Type-Options`, `X-Frame-Options`, `Referrer-Policy`
6. **nginx basic auth** — htpasswd on API, pgAdmin, and aisoc. NOT on kbaas (OpenWebUI handles JWT auth) or districtsolutions.ai (public).
7. **fail2ban** — Auto-bans IPs: 3 failed auth → 24hr ban, 1 bot probe → permanent ban, 5 rate violations/1min → 12hr ban, 2 SSH fails → permanent ban. Covers all subdomains via `*_error.log` glob.
8. **Service-level auth** — OpenWebUI has its own login (JWT tokens). pgAdmin has its own login (email/password).
9. **AWS IAM** — EC2 instance role for S3, SQS, and ECR access (no hardcoded credentials)
10. **SOC database** — Separate `socagent` database with its own user and password (env var configured)

---

## SSL Certificate

Single multi-SAN certificate via Let's Encrypt (HTTP-01 challenge):

```
districtsolutions.ai
api.districtsolutions.ai
kbaas.districtsolutions.ai
aisoc.districtsolutions.ai
pg.districtsolutions.ai
msg.districtsolutions.ai
git.districtsolutions.ai
```

Issued/renewed via `scripts/issue-cert.sh` and `scripts/renew-cert.sh`. Stored at `data/letsencrypt/live/districtsolutions.ai/`.

---

## Adding a New Subdomain / Service

Checklist for adding a new service (e.g., `foo.districtsolutions.ai`):

### 1. DNS Record
Add an A record for `foo.districtsolutions.ai` → `34.234.159.163` at your DNS provider (Namecheap).

### 2. SSL Certificate
Add the new domain to the certbot config and reissue:
- Edit `stack/certbot/certbot.yaml` — add `-d foo.${DOMAIN}` to the certbot entrypoint
- Run `./scripts/issue-cert.sh` to reissue with the new SAN
- Restart nginx: `./scripts/restart-nginx.sh`

### 3. Nginx Config
Create `stack/nginx/conf.d/foo.districtsolutions.ai.conf`:
- Copy an existing conf as a template (use `api.*.conf` for basic auth, `kbaas.*.conf` for no auth)
- Set `server_name foo.districtsolutions.ai`
- Set `proxy_pass` to the container's internal hostname and port
- Add to the HTTP→HTTPS redirect `server_name` list in `stack/nginx/nginx.conf`

### 4. Docker Compose
Create `stack/foo/docker-compose.yaml`:
- Use `core-net` as an external network
- If the service needs a database, give it its own postgres container (not the shared `biz-tool-postgres`) — see `stack/gitea/` or `stack/mattermost/` for examples
- Data volumes should go under `data/foo/`

### 5. Environment Variables
- Add any new env vars to `.env.example` with `changeme` defaults
- Add the real values to `/opt/ds/env.sh` on the server

### 6. Restart Script
Update `scripts/restart-all.sh`:
- Add `mkdir -p` for any new data directories
- Add `restart_service foo` in the correct order (before nginx, after any dependencies)

### 7. Deploy
```bash
cd /opt/ds/core
git pull
./scripts/issue-cert.sh    # reissue cert with new SAN
./scripts/restart-all.sh   # starts everything including new service
```

### 8. Verify
```bash
curl -I https://foo.districtsolutions.ai
# Should return 200 (or 401 if behind basic auth)
```

### 9. Update Documentation
- Update the services table in `notes/01-getting-started.md`
- Update the subdomain routing table, containers table, databases section, and port map in `notes/02-architecture.md`
- Update the URLs table in `notes/03-quick-reference.md`
- Add the subdomain to the DNS records table in `notes/01-getting-started.md` Step 4

---

## File Locations

| What | Path |
|------|------|
| Core project root | `/opt/ds/core` |
| Core Python package | `/opt/ds/core/core/` |
| SOC backend (API, orchestrator, tools) | `/opt/ds/core/core/soc/` |
| SOC frontend (Next.js) | `/opt/ds/ai-soc/soc-agent 2/web/` |
| District Solutions website | `/opt/ds/districtsolutions/` |
| Docker compose files | `/opt/ds/core/stack/{service}/` |
| CloudFormation templates | `/opt/ds/core/stack/cf/` |
| Nginx configs | `/opt/ds/core/stack/nginx/` |
| Fail2ban configs | `/opt/ds/core/stack/fail2ban/` |
| Scripts | `/opt/ds/core/scripts/` |
| SSL certificates | `/opt/ds/core/data/letsencrypt/live/districtsolutions.ai/` |
| Nginx logs | `/opt/ds/core/data/nginx/logs/` |
| OpenWebUI data | `/opt/ds/core/data/oweb/` |
| Mattermost data | `/opt/ds/core/data/mattermost/` |
| Mattermost DB | `/opt/ds/core/data/mattermost/db/` |
| Gitea data | `/opt/ds/core/data/gitea/website/` |
| Gitea DB | `/opt/ds/core/data/gitea/db/` |
| Environment secrets | `/opt/ds/env.sh` |

## Port Map

| Port | Service | Exposure |
|------|---------|----------|
| 80 | nginx (HTTP → HTTPS redirect + ACME challenge) | Public |
| 443 | nginx (HTTPS) | Public |
| 2222 | Gitea SSH | Public (git clone via SSH) |
| 8000 | BizTool API (FastAPI) | Docker network (via nginx) |
| 8080 | Open WebUI | Docker network (via nginx) |
| 9322 | Open WebUI (host mapping) | localhost / LAN |
| 9099 | Pipelines | Docker network |
| 8065 | Mattermost | Docker network (via nginx) |
| 3000 | SOC Web (Next.js) | Docker network (via nginx) |
| 3001 | SOC Web (host mapping) | localhost / LAN |
| 5432 | Postgres (biztool + socagent) | CIDR-locked in SG + Docker network |
| 80 | district-web (internal) | Docker network (via nginx) |
| 80 | pg-admin (internal) | Docker network (via nginx) |
| 22 | SSH | CIDR-locked in SG |

## ECR Image Registry

All custom container images are stored in AWS ECR. Docker compose files reference ECR images by default — the server pulls pre-built images instead of building locally, saving disk space and startup time.

**Registry:** `381492049589.dkr.ecr.us-east-1.amazonaws.com/core/prod/{service}`

| ECR Repository | Image | Lifecycle |
|----------------|-------|-----------|
| `core/prod/api` | Core API (FastAPI) | Keep last 10 images |
| `core/prod/worker` | Core worker (SQS consumer) | Keep last 10 images |
| `core/prod/soc-worker` | SOC worker (LangGraph + scheduler) | Keep last 10 images |
| `core/prod/soc-web` | SOC frontend (Next.js) | Keep last 10 images |
| `core/prod/district-web` | Company website | Keep last 10 images |

### Build & Deploy Workflow

```
1. Make code changes
2. Build & push to ECR:   ./scripts/build-push-all.sh        (all services)
                           ./scripts/build-push-api.sh        (single service)
3. Restart services:      ./scripts/restart-all.sh            (pull from ECR)
                           ./scripts/restart-api.sh            (single service)
4. Clean up old images:   ./scripts/docker-prune.sh
```

The `restart-all.sh` script supports a `--build` flag to build locally instead of pulling from ECR (useful when ECR is unreachable or for quick dev iteration).

### First-Time ECR Setup

```bash
# 1. Deploy the ECR repositories
aws cloudformation deploy \
    --template-file stack/cf/ecr/ecr.yaml \
    --stack-name core-ecr \
    --parameter-overrides Environment=prod

# 2. Deploy the IAM policy (attaches to ec2-ssm-role)
aws cloudformation deploy \
    --template-file stack/cf/ecr/ecr-policy.yaml \
    --stack-name core-ecr-policy \
    --capabilities CAPABILITY_NAMED_IAM

# 3. Build and push all images for the first time
./scripts/build-push-all.sh
```

## Scripts

| Script | Purpose |
|--------|---------|
| **Lifecycle** | |
| `scripts/restart-all.sh` | Pull from ECR and start all services in order (use `--build` for local builds) |
| `scripts/restart-api.sh` | Pull and restart API only |
| `scripts/restart-worker.sh` | Pull and restart worker only |
| `scripts/restart-soc-worker.sh` | Pull and restart SOC worker only |
| `scripts/restart-soc-web.sh` | Pull and restart SOC web only |
| `scripts/restart-district-web.sh` | Pull and restart district website only |
| `scripts/restart-db.sh` | Restart Postgres |
| `scripts/restart-oweb.sh` | Pull and restart Open WebUI |
| `scripts/restart-nginx.sh` | Reload nginx configuration |
| **Build & Push** | |
| `scripts/build-push-all.sh` | Build and push all custom images to ECR (accepts service names as args) |
| `scripts/build-push-api.sh` | Build and push API image to ECR |
| `scripts/build-push-worker.sh` | Build and push worker image to ECR |
| `scripts/build-push-soc-worker.sh` | Build and push SOC worker image to ECR |
| `scripts/build-push-soc-web.sh` | Build and push SOC web image to ECR |
| `scripts/build-push-district-web.sh` | Build and push district website image to ECR |
| **Infrastructure** | |
| `scripts/docker-prune.sh` | Clean up dangling images and build cache to reclaim disk space |
| `scripts/issue-cert.sh` | Issue/renew Let's Encrypt SSL certificate |
| `scripts/renew-cert.sh` | Renew existing certificate |
| `scripts/generate-htpasswd.sh` | Generate basic auth credentials |
| `scripts/setup-fail2ban.sh` | Install and configure fail2ban |
| **Shared** | |
| `scripts/common.sh` | Shared ECR variables and helpers (sourced by other scripts) |
