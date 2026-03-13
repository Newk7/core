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
                     │  SG: 22,80,443│
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
                │                              └──────────────┘
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
                │    ┌──────────────┐
                └───▶│ district-web │  (districtsolutions.ai)
                     │    :80       │  React SPA in nginx container
                     └──────────────┘
```

## Subdomain Routing

| URL | Nginx Auth | Backend | Purpose |
|-----|-----------|---------|---------|
| `https://districtsolutions.ai` | None (public) | district-web:80 | Company website (React SPA) |
| `https://kb.districtsolutions.ai` | None (OWU JWT) | biz-tool-oweb:8080 | AI chat / knowledge base |
| `https://api.districtsolutions.ai` | Basic auth | biz-tool-api:8000 | REST API for tasks + contact form |

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
                     ports 22,80,443           ├─ TLS 1.2/1.3 (purchased cert)
                     CIDR whitelist            ├─ basic auth (API endpoints)
                     for SSH                   ├─ rate limiting (10r/s general, 5r/s auth)
                                               ├─ security headers
                                               ├─ default server drops unknown hosts
                                               │
                                           fail2ban
                                        (bans auth fails + bot scans + rate violations)
```

1. **EC2 Security Group** - Ports 22, 80, 443 all CIDR-locked to team IPs pre-launch. At go-live, open 80/443 to 0.0.0.0/0 (keep SSH CIDR-locked). See Step 13 in 01-getting-started.md
2. **nginx default server** - Drops connections with no matching Host header (returns 444)
3. **nginx TLS** - TLSv1.2/1.3 with strong ECDHE ciphers, purchased cert
4. **nginx rate limiting** - 10 req/s general, 5 req/s on auth endpoints
5. **nginx security headers** - `X-Content-Type-Options`, `X-Frame-Options`, `Referrer-Policy`
6. **nginx basic auth** - htpasswd on API endpoints. NOT on kb subdomain (OWU handles JWT auth)
7. **fail2ban** - Auto-bans IPs: 5 failed auth attempts → 1hr ban, 2 bot scans → 1hr ban, 10 rate violations in 2min → 10min ban
8. **Service-level auth** - Open WebUI has its own login (JWT tokens)
9. **AWS IAM** - EC2 instance role for S3 and SQS access (no hardcoded credentials)

## File Locations

| What | Path |
|------|------|
| Project root | /home/ec2-user/core |
| Python package | /home/ec2-user/core/core/ |
| Docker compose files | /home/ec2-user/core/stack/{service}/ |
| Website source | /home/ec2-user/frontend/district-web/ (or local dev repo) |
| CloudFormation templates | /home/ec2-user/core/stack/cf/ |
| Nginx configs | /home/ec2-user/core/stack/nginx/ |
| Fail2ban configs | /home/ec2-user/core/stack/fail2ban/ |
| Scripts | /home/ec2-user/core/scripts/ |
| SSL certificates | /home/ec2-user/core/data/ssl/ |
| Nginx logs | /home/ec2-user/core/data/nginx/logs/ |
| Environment secrets | /home/ec2-user/core/.env |

## Port Map

| Port | Service | Exposure |
|------|---------|----------|
| 80 | nginx (HTTP → HTTPS redirect) | Public |
| 80 | district-web (internal nginx) | Docker network (via nginx) |
| 443 | nginx (HTTPS) | Public |
| 8000 | BizTool API (FastAPI) | Docker network (via nginx) |
| 8080 | Open WebUI | Docker network (via nginx) |
| 9322 | Open WebUI (host mapping) | localhost / LAN |
| 5432 | Postgres | Docker network |
| 22 | SSH | CIDR-locked in SG |
