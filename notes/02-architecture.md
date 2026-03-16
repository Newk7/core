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
    ┌────────────────────────┼────────────────────────┐
    │                        │                        │
    ▼                        ▼                        ▼
┌─────────┐          ┌──────────────┐         ┌──────────────┐
│  nginx  │─────────▶│  open-webui  │         │   postgres   │
│ :80/:443│  proxy   │    :8080     │         │    :5432     │
│ + auth  │─────┐    └──────────────┘         └──────────────┘
└─────────┘     │
                │    ┌──────────────┐         ┌──────────────┐
                ├───▶│   api        │────────▶│  AWS SQS     │
                │    │   :8000      │         │  task queue   │
                │    └──────────────┘         │  result queue │
                │                             └──────────────┘
                │    ┌──────────────┐         ┌──────────────┐
                │    │   worker     │────────▶│  AWS S3      │
                │    │  (no port)   │         │  task data   │
                │    └──────────────┘         └──────────────┘
                │
                │    ┌──────────────┐
                │    │  fail2ban    │
                │    │ (host-level) │
                │    └──────────────┘
                │
                ├───▶┌──────────────┐
                │    │  pg-admin    │  (pg.districtsolutions.ai)
                │    │    :80       │  pgAdmin4 (basic auth + pgAdmin login)
                │    └──────────────┘
                │
                └───▶┌──────────────┐
                     │ district-web │  (districtsolutions.ai)
                     │    :80       │  React SPA in nginx container
                     └──────────────┘
```

## Subdomain Routing

| URL | Nginx Auth | Backend | Purpose |
|-----|-----------|---------|---------|
| `https://districtsolutions.ai` | None (public) | district-web:80 | Company website (React SPA) |
| `https://kb.districtsolutions.ai` | None (OWU JWT) | biz-tool-oweb:8080 | AI chat / knowledge base |
| `https://api.districtsolutions.ai` | Basic auth | biz-tool-api:8000 | REST API for tasks + contact form |
| `https://pg.districtsolutions.ai` | Basic auth + pgAdmin login | pg-admin:80 | pgAdmin4 database UI |

## SQS Task Architecture

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

## Security Layers

```
Internet ──▶ DNS ──▶ EC2 Security Group ──▶ nginx ──▶ Service
                          │                    │
                     80/443 open to            ├─ TLS 1.2/1.3 (Let's Encrypt cert, auto-renewed)
                     0.0.0.0/0                 ├─ basic auth (API + pgAdmin)
                     22 CIDR-locked            ├─ rate limiting (10r/s general, 5r/s auth)
                     5432 CIDR-locked          ├─ security headers
                                               ├─ default server drops unknown hosts
                                               │
                                           fail2ban
                                        (bans auth fails + bot scans + rate violations)
```

1. **EC2 Security Group** - Ports 80/443 open to `0.0.0.0/0` (required for Let's Encrypt + public site). SSH (22) CIDR-locked. Postgres (5432) CIDR-locked via `PostgresCIDR`/`PostgresCIDR1` parameters in `host.yaml`.
2. **nginx default server** - Drops connections with no matching Host header (returns 444)
3. **nginx TLS** - TLSv1.2/1.3 with strong ECDHE ciphers, Let's Encrypt cert (auto-renewed via cron)
4. **nginx rate limiting** - 10 req/s general, 5 req/s on auth endpoints. pgAdmin has no rate limit (double-protected by auth layers instead).
5. **nginx security headers** - `X-Content-Type-Options`, `X-Frame-Options`, `Referrer-Policy`
6. **nginx basic auth** - htpasswd on API and pgAdmin endpoints. NOT on kb subdomain (OWU handles JWT auth)
7. **fail2ban** - Auto-bans IPs: 3 failed auth → 24hr ban, 1 bot probe → permanent ban, 5 rate violations/1min → 12hr ban, 2 SSH fails → permanent ban. Covers `pg.` automatically via `*_error.log` glob in `nginx-http-auth` jail.
8. **Service-level auth** - Open WebUI has its own login (JWT tokens). pgAdmin has its own login (email/password).
9. **AWS IAM** - EC2 instance role for S3 and SQS access (no hardcoded credentials)

## File Locations

| What | Path |
|------|------|
| Project root | /opt/ds/core |
| Python package | /opt/ds/core/core/ |
| Docker compose files | /opt/ds/core/stack/{service}/ |
| Website source | /opt/ds/districtsolutions/ |
| CloudFormation templates | /opt/ds/core/stack/cf/ |
| Nginx configs | /opt/ds/core/stack/nginx/ |
| Fail2ban configs | /opt/ds/core/stack/fail2ban/ |
| Scripts | /opt/ds/core/scripts/ |
| SSL certificates | /opt/ds/core/data/letsencrypt/live/districtsolutions.ai/ |
| Nginx logs | /opt/ds/core/data/nginx/logs/ |
| Environment secrets | /opt/ds/core/.env |

## Port Map

| Port | Service | Exposure |
|------|---------|----------|
| 80 | nginx (HTTP → HTTPS redirect) | Public (0.0.0.0/0) |
| 80 | district-web (internal nginx) | Docker network (via nginx) |
| 80 | pg-admin (pgAdmin4) | Docker network (via nginx) |
| 443 | nginx (HTTPS) | Public (0.0.0.0/0) |
| 8000 | BizTool API (FastAPI) | Docker network (via nginx) |
| 8080 | Open WebUI | Docker network (via nginx) |
| 9322 | Open WebUI (host mapping) | localhost / LAN |
| 5432 | Postgres | CIDR-locked in SG + Docker network |
| 22 | SSH | CIDR-locked in SG |
