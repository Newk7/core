# Getting Started - District Solutions AI Infrastructure

## Machine Profile

| Component | Value |
|-----------|-------|
| Host | AWS EC2 t3.medium (Amazon Linux 2023) |
| Region | us-east-1 |
| VPC | vpc-0dd28884da7e4d4eb (10.0.0.0/16) |
| Subnet | subnet-0531a7a14eef69db2 (10.0.0.0/24, us-east-1b, public) |
| Public IP | 34.234.159.163 |
| Domain | districtsolutions.ai (Namecheap DNS, Let's Encrypt cert) |
| Python | 3.11 (container) |
| Account | 381492049589 |

## Services

| Service | Container | Port | Purpose |
|---------|-----------|------|---------|
| nginx | core-nginx | 80, 443 | TLS termination, reverse proxy, basic auth |
| Website | district-web | 80 (internal) | Company website SPA (districtsolutions.ai) |
| Open WebUI | biz-tool-oweb | 9322 → 8080 | AI chat / knowledge base (kbaas.districtsolutions.ai) |
| Pipelines | core-pipelines | 9099 | OpenWebUI custom pipelines |
| API | biz-tool-api | 8000 | FastAPI REST API for task pipeline + contact form |
| Worker | biz-tool-worker | — | SQS polling task processor |
| SOC Worker | soc-worker | — | LangGraph orchestration + scheduler |
| SOC Web | soc-web | 3000 | AI-SOC dashboard (aisoc.districtsolutions.ai) |
| Postgres | biz-tool-postgres | 5432 | Core + SOC databases (biztool, socagent) |
| pgAdmin | pg-admin | 80 (internal) | Database management UI (pg.districtsolutions.ai) |
| Mattermost | core-mattermost | 8065 | Messaging platform (msg.districtsolutions.ai) |
| Mattermost DB | mattermost-pg | — | Dedicated Mattermost postgres |
| Gitea | gitea | 8080, 2222 | Self-hosted git (git.districtsolutions.ai) |
| Gitea DB | gitea-pg | — | Dedicated Gitea postgres |
| Gitea Redis | gitea-redis | — | Gitea caching |
| fail2ban | (host-level) | — | Auto-ban brute force + bot scans |

---

## Step-by-Step Setup Guide

### Step 1: Deploy AWS Infrastructure

CloudFormation stacks (if not already deployed):

```bash
# EC2 build host
aws cloudformation deploy \
  --template-file stack/cf/build-host/host.yaml \
  --stack-name AI-BizTool \
  --capabilities CAPABILITY_NAMED_IAM \
  --region us-east-1

# S3 task data bucket
aws cloudformation deploy \
  --template-file stack/cf/s3/s3.yaml \
  --stack-name biz-tool-s3 \
  --region us-east-1

# SQS queues (task + result + DLQs)
aws cloudformation deploy \
  --template-file stack/cf/sqs/sqs.yaml \
  --stack-name biz-tool-sqs \
  --region us-east-1
```

**SES (email for contact form):**
```bash
aws cloudformation deploy \
  --template-file stack/cf/ses/ses.yaml \
  --stack-name biz-tool-ses \
  --capabilities CAPABILITY_NAMED_IAM \
  --region us-east-1
```

After SES deploy, add these DNS records at your provider (Namecheap):

| Type | Name | Value |
|------|------|-------|
| CNAME | `<token1>._domainkey.districtsolutions.ai` | `<token1>.dkim.amazonses.com` |
| CNAME | `<token2>._domainkey.districtsolutions.ai` | `<token2>.dkim.amazonses.com` |
| CNAME | `<token3>._domainkey.districtsolutions.ai` | `<token3>.dkim.amazonses.com` |
| MX | `mail.districtsolutions.ai` | `10 feedback-smtp.us-east-1.amazonses.com` |
| TXT | `mail.districtsolutions.ai` | `v=spf1 include:amazonses.com ~all` |

Get the DKIM token values from the SES console: Verified identities > districtsolutions.ai.

Then request production access (out of sandbox): SES console > Account dashboard > Request production access.

**Verify:**
```bash
aws cloudformation describe-stacks --stack-name AI-BizTool --query 'Stacks[0].StackStatus'
aws s3 ls | grep biz-tool
aws sqs list-queues --queue-name-prefix biz-tool
aws ses get-email-identity --email-identity districtsolutions.ai --query 'DkimAttributes.Status'
# Expected: "SUCCESS" (after DNS propagation, may take 10-60 minutes)
```

---

### Step 2: SSH into EC2 and Install Docker Plugins

The CloudFormation UserData installs Docker but not the Compose or Buildx plugins:

```bash
ssh kevin@34.234.159.163

# Install Docker Compose v2
sudo mkdir -p /usr/local/lib/docker/cli-plugins
sudo curl -fSL https://github.com/docker/compose/releases/latest/download/docker-compose-linux-x86_64 \
  -o /usr/local/lib/docker/cli-plugins/docker-compose
sudo chmod +x /usr/local/lib/docker/cli-plugins/docker-compose

# Install Docker Buildx (v0.17.0+ required)
sudo curl -fSL https://github.com/docker/buildx/releases/download/v0.19.3/buildx-v0.19.3.linux-amd64 \
  -o /usr/local/lib/docker/cli-plugins/docker-buildx
sudo chmod +x /usr/local/lib/docker/cli-plugins/docker-buildx

# Disable the host-level nginx (conflicts with Docker nginx on ports 80/443)
sudo systemctl stop nginx && sudo systemctl disable nginx

# Verify
docker compose version
docker buildx version
```

### Step 2b: Clone the Repos

```bash
cd /opt/ds
git clone <your-git-remote> core
cd core
```

---

### Step 3: Create Your .env File

```bash
cp .env.example .env
```

Edit `.env` and set real values. Generate strong passwords:
```bash
python3 -c "import secrets; print(secrets.token_urlsafe(32))"
```

Fill in:
```
HTPASSWD_PASS=<strong password for nginx basic auth>
POSTGRES_PASSWORD=<random 32+ char string>
POSTGRES_TASK_PW=<same as POSTGRES_PASSWORD>
PGADMIN_EMAIL=admin@districtsolutions.ai
PGADMIN_PASSWORD=<strong password for pgAdmin login>
OWEB_SECRET_KEY=<random 32+ char string>
ANTHROPIC_API_KEY=<your key>
OPENAI_API_KEY=<your key, if using>
# SES uses IAM role - no email credentials needed
```

---

### Step 4: DNS Setup

Your A record is already set:
```
districtsolutions.ai.  1799  IN  A  34.234.159.163
```

Add these additional A records at your DNS provider:

| Type | Name | Content | TTL |
|------|------|---------|-----|
| A | `@` | 34.234.159.163 | 1800 |
| A | `kbaas` | 34.234.159.163 | 1800 |
| A | `api` | 34.234.159.163 | 1800 |
| A | `pg` | 34.234.159.163 | 1800 |
| A | `aisoc` | 34.234.159.163 | 1800 |
| A | `msg` | 34.234.159.163 | 1800 |
| A | `git` | 34.234.159.163 | 1800 |

**Verify:**
```bash
dig districtsolutions.ai
dig kb.districtsolutions.ai
dig api.districtsolutions.ai
dig pg.districtsolutions.ai
# All should return 34.234.159.163
```

---

### Step 5: Issue SSL Certificate (Let's Encrypt + Certbot)

Free auto-renewing SSL certs from Let's Encrypt using HTTP-01 challenge. No paid cert, no CSR, no `.key` file to manage — certbot handles everything. Domain stays on Namecheap DNS, no Cloudflare needed.

**Prerequisites:**
- Port 80 must be reachable from the internet (`0.0.0.0/0` — already set in current `host.yaml`)
- DNS A records for all subdomains must point to this server
- nginx must be running (it serves the ACME challenge files)
- All upstream containers referenced in `conf.d/` must be running before nginx reload (or use `--force-recreate` to restart nginx after adding new vhosts)

**Step 5a: Verify port 80 is open:**

The current `host.yaml` has port 80/443 open to `0.0.0.0/0` — required for Let's Encrypt HTTP-01 challenge. If it's ever CIDR-locked, update the SG before running certbot.

**Step 5b: Make sure `.env` has these values:**
```bash
DOMAIN=districtsolutions.ai
ADMIN_EMAIL=hello@districtsolutions.ai
```

**Step 5c: Start nginx first** (it serves the ACME challenge directory):
```bash
cd /opt/ds/core

# Create required directories
mkdir -p data/letsencrypt data/certbot-webroot data/nginx/logs

# Start nginx (it will fail on HTTPS until certs exist, but port 80 works)
# For first-time setup, temporarily comment out the 443 listeners or use a self-signed cert
# See "First-time bootstrap" below
```

**Step 5d: Issue the cert:**
```bash
./scripts/issue-cert.sh
```

Expected output:
```
=== Issuing Let's Encrypt cert for districtsolutions.ai ===
...
cert issued for districtsolutions.ai, api.districtsolutions.ai, pg.districtsolutions.ai
Subject: CN = districtsolutions.ai
DNS:api.districtsolutions.ai, DNS:districtsolutions.ai, DNS:pg.districtsolutions.ai
```

**Step 5e: Verify certs:**
```bash
ls data/letsencrypt/live/districtsolutions.ai/
# Should show: cert.pem  chain.pem  fullchain.pem  privkey.pem  README

openssl x509 -in data/letsencrypt/live/districtsolutions.ai/cert.pem -text -noout | grep -E "Subject:|DNS:"
# Should show: CN=districtsolutions.ai with SANs for all 3 subdomains

openssl x509 -in data/letsencrypt/live/districtsolutions.ai/cert.pem -noout -enddate
# Should show ~90 days from now
```

**Step 5f: Set up auto-renewal** (certs expire every 90 days):
```bash
crontab -e
```
Add this line:
```cron
# Renew Let's Encrypt certs twice a month (certbot only renews if within 30 days of expiry)
0 3 1,15 * * /opt/ds/core/scripts/renew-cert.sh >> /var/log/cert-renewal.log 2>&1
```

**First-time bootstrap (chicken-and-egg problem):**

nginx needs certs to start HTTPS, but certbot needs nginx running on port 80 to serve the challenge. Additionally, nginx fails to start if upstream containers (district-web, biz-tool-api, biz-tool-oweb) aren't running. For the very first cert issuance:

```bash
# 1. Move configs for services that aren't running yet
mkdir -p stack/nginx/conf.d/disabled
mv stack/nginx/conf.d/api.districtsolutions.ai.conf stack/nginx/conf.d/disabled/
mv stack/nginx/conf.d/kb.districtsolutions.ai.conf stack/nginx/conf.d/disabled/
mv stack/nginx/conf.d/districtsolutions.ai.conf stack/nginx/conf.d/disabled/

# 2. Generate a temporary self-signed cert so nginx can start
mkdir -p data/letsencrypt/live/districtsolutions.ai
openssl req -x509 -nodes -days 1 -newkey rsa:2048 \
  -keyout data/letsencrypt/live/districtsolutions.ai/privkey.pem \
  -out data/letsencrypt/live/districtsolutions.ai/fullchain.pem \
  -subj "/CN=districtsolutions.ai"

# 3. Start nginx (only base config with port 80 ACME challenge)
cd stack/nginx && docker compose -f nginx.yaml up -d && cd ../..

# 4. Verify port 80 is responding
curl -I -H "Host: districtsolutions.ai" http://localhost/.well-known/acme-challenge/test
# Should return 404 from nginx (that's fine)

# 5. Issue the real cert
./scripts/issue-cert.sh

# 6. Clean up old self-signed cert remnants if re-issuing
# rm -rf data/letsencrypt/live/districtsolutions.ai
# rm -rf data/letsencrypt/archive/districtsolutions.ai
# rm -f data/letsencrypt/renewal/districtsolutions.ai.conf

# 7. Move configs back and restart nginx
mv stack/nginx/conf.d/disabled/*.conf stack/nginx/conf.d/
rmdir stack/nginx/conf.d/disabled
cd stack/nginx && docker compose -f nginx.yaml down && docker compose -f nginx.yaml up -d && cd ../..
# Note: nginx will fail if upstream services aren't running yet — start them first (Step 8)
```

> **Cert files:** nginx is configured to read from `data/letsencrypt/live/districtsolutions.ai/`:
> - `fullchain.pem` → `ssl_certificate`
> - `privkey.pem` → `ssl_certificate_key`
>
> These are managed entirely by certbot. No manual key generation or Namecheap cert purchase needed.

<details>
<summary><strong>Reference: Cloudflare DNS-01 alternative (wildcard certs)</strong></summary>

If you later move DNS to Cloudflare, you can use DNS-01 challenge for wildcard certs (`*.districtsolutions.ai`) without needing port 80 open. See `newk-ai/stack/certbot/` for a working implementation. This requires a Cloudflare API token with `Zone:DNS:Edit` permission.

</details>

---

### Step 6: Create Docker Network and Generate htpasswd

```bash
cd /opt/ds/core

# Create the shared docker network
docker network create core-net

# Install htpasswd (Amazon Linux 2023)
sudo dnf install -y httpd-tools

# Source env and generate htpasswd
source .env
./scripts/generate-htpasswd.sh
```

**Verify:**
```bash
cat stack/nginx/htpasswd
# Should show: kevin:$apr1$...hashed_password...
```

---

### Step 7: Clone the Website Frontend

The District Solutions website is a separate React app built into a Docker container.
The docker-compose at `stack/district-web/` builds from `/opt/ds/districtsolutions`.

```bash
cd /opt/ds
git clone <district-solutions-git-remote> districtsolutions
```

Expected directory layout on EC2:
```
/opt/ds/
  core/                    # This repo (infra, API, worker)
  districtsolutions/       # District Solutions website (React SPA)
```

---

### Step 8: Start All Services

```bash
cd /opt/ds/core
./scripts/restart-all.sh
```

This starts in order: postgres → open-webui → api → worker → district-web → nginx

**Start pgAdmin separately:**
```bash
docker compose -f stack/db/pg-admin.yaml --env-file .env up -d
```

**Verify everything is running:**
```bash
docker ps
```

Expected containers:
```
biz-tool-postgres   postgres:16-alpine         port 5432
biz-tool-oweb       open-webui:latest          port 9322
biz-tool-api        biz-tool-api               port 8000
biz-tool-worker     biz-tool-worker            (no port)
district-web        district-web               (internal :80)
pg-admin            dpage/pgadmin4:latest      (internal :80)
core-nginx          nginx:alpine               port 80, 443
```

**Test each service:**
```bash
# Postgres
docker exec biz-tool-postgres pg_isready -U biztool
# Expected: accepting connections

# Open WebUI (direct, bypassing nginx)
curl -s http://localhost:9322 | head -5
# Expected: HTML response

# API health check
curl -s http://localhost:8000/health
# Expected: {"status":"ok","timestamp":"...","version":"0.1.0"}

# Nginx HTTPS (will validate with real cert)
curl -I https://districtsolutions.ai
# Expected: HTTP/2 200

# kb subdomain (OWU login page, no basic auth)
curl -I https://kb.districtsolutions.ai
# Expected: HTTP/2 200

# API subdomain (behind basic auth)
curl -I https://api.districtsolutions.ai
# Expected: HTTP/2 401

curl -u kevin:YOUR_HTPASSWD_PASS https://api.districtsolutions.ai/health
# Expected: {"status":"ok",...}
```

---

### Step 9: Install and Configure fail2ban

```bash
sudo ./scripts/setup-fail2ban.sh
```

Or manually:
```bash
sudo dnf install -y fail2ban

# Copy configs
sudo cp stack/fail2ban/jail.local /etc/fail2ban/jail.local
sudo cp stack/fail2ban/filter.d/nginx-auth.conf /etc/fail2ban/filter.d/nginx-auth.conf
sudo cp stack/fail2ban/filter.d/nginx-botsearch.conf /etc/fail2ban/filter.d/nginx-botsearch.conf

sudo systemctl enable fail2ban
sudo systemctl restart fail2ban
```

**Verify jails are active:**
```bash
sudo fail2ban-client status
# Expected: nginx-http-auth, nginx-botsearch, nginx-limit-req, sshd

sudo fail2ban-client status nginx-http-auth
# Should show: Currently failed: 0, Currently banned: 0
# IMPORTANT: "File list:" should show nginx log paths, NOT "No file is currently monitored"
```

**Ban thresholds:**

| Jail | Trigger | Ban Duration |
|------|---------|-------------|
| nginx-http-auth | 3 failed logins in 5min | 24 hours |
| nginx-botsearch | 1 probe (.env, .git, wp-admin, etc.) | **Permanent** |
| nginx-limit-req | 5 rate limit hits in 1min | 12 hours |
| sshd | 2 failed SSH attempts | **Permanent** |

**Test fail2ban** (from another machine):
```bash
# Make 4 failed auth attempts (exceeds maxretry=3)
for i in {1..4}; do curl -sk -u wrong:wrong https://api.districtsolutions.ai; done

# Check if the IP got banned (on EC2)
sudo fail2ban-client status nginx-http-auth
# Should show the client's IP in the banned list

# Unban yourself if needed
sudo fail2ban-client set nginx-http-auth unbanip <your-ip>

# Unban from ALL jails at once
sudo fail2ban-client unban <your-ip>

# List all currently banned IPs
sudo fail2ban-client banned
```

**Important:** The jail.local uses `backend = auto`. Without this, fail2ban may default to the systemd journal backend and ignore the `logpath` entirely.

---

### Step 10: Verify External Access

From your local machine (MacBook):

```bash
# Test DNS resolution
dig districtsolutions.ai
dig kb.districtsolutions.ai
# Both should return 34.234.159.163

# Test landing page (public, no auth)
curl -I https://districtsolutions.ai
# Expected: HTTP/2 200

# Test Open WebUI (no nginx auth, OWU has its own login)
curl -I https://kb.districtsolutions.ai
# Expected: HTTP/2 200 (OWU login page)

# Test API (behind basic auth)
curl -I https://api.districtsolutions.ai
# Expected: HTTP/2 401

curl -u kevin:YOUR_PASS https://api.districtsolutions.ai/health
# Expected: {"status":"ok",...}

# Test security headers
curl -sI https://districtsolutions.ai | grep -E "X-Content-Type|X-Frame|Referrer"
# Expected:
#   X-Content-Type-Options: nosniff
#   X-Frame-Options: SAMEORIGIN
#   Referrer-Policy: strict-origin-when-cross-origin

# Test rate limiting (should get 503 after burst)
for i in {1..25}; do curl -so /dev/null -w "%{http_code}\n" https://districtsolutions.ai & done; wait
# Some should show 503 (rate limited)
```

---

### Step 11: Configure Open WebUI

1. Open `https://kb.districtsolutions.ai` in your browser
2. Create your admin account on first visit
3. Configure AI providers in Admin Settings:
   - Anthropic API key (for Claude)
   - OpenAI API key (if using)
4. Set up any tool servers (see [openapi-tool-servers.md](openapi-tool-servers.md))

---

### Step 12: Security Group Check (Pre-Launch)

During development, all ports are CIDR-locked to team IPs only. Verify:

```bash
aws ec2 describe-security-groups \
  --filters "Name=group-name,Values=*BizTool*" \
  --query 'SecurityGroups[0].IpPermissions[*].{Port:FromPort,CIDR:IpRanges[0].CidrIp}'
```

Current SG rules:
| Port | CIDR | Purpose |
|------|------|---------|
| 22 | team IPs only | SSH access |
| 80 | 0.0.0.0/0 | HTTP (redirects to HTTPS; needed for Let's Encrypt) |
| 443 | 0.0.0.0/0 | HTTPS (public) |
| 5432 | team IPs only | Postgres direct access (via `PostgresCIDR`/`PostgresCIDR1` params) |

> **Note:** The CloudFormation template (`stack/cf/build-host/host.yaml`) manages these rules. Update `PostgresCIDR`/`PostgresCIDR1` parameters to change which IPs can connect directly to Postgres on port 5432.

---

### Step 13: Go-Live Checklist

Ports 80/443 are already open to `0.0.0.0/0`. Go-live steps:

1. **Verify public access** from a non-whitelisted IP (e.g., mobile hotspot):
   ```bash
   curl -I https://districtsolutions.ai
   # Expected: HTTP/2 200

   curl -I https://api.districtsolutions.ai/health
   # Expected: HTTP/2 200 (health is public)

   curl -I https://api.districtsolutions.ai/api/v1/tasks
   # Expected: HTTP/2 401 (basic auth still protects API endpoints)
   ```

3. **Confirm these remain protected:**
   - SSH (port 22) — still CIDR-locked to team IPs
   - API endpoints (`/api/v1/*`) — still behind nginx basic auth (except `/health` and `/api/v1/contact`)
   - Open WebUI — has its own JWT login, no nginx auth needed

4. **Optional: Remove nginx basic auth from API** when client apps are ready to authenticate differently. The comment in `stack/nginx/conf.d/api.districtsolutions.ai.conf` says "remove when ready to go live."

---

## Troubleshooting

### Nginx won't start
```bash
# Check config syntax
docker run --rm \
  -v $(pwd)/stack/nginx/nginx.conf:/etc/nginx/nginx.conf:ro \
  -v $(pwd)/stack/nginx/conf.d:/etc/nginx/conf.d:ro \
  nginx:alpine nginx -t

# Check logs
docker logs core-nginx
```

### nginx.conf changes not picked up after git pull
`nginx.conf` is mounted as a file bind (not a directory). `git pull` replaces the file's inode, so `nginx -s reload` reads the stale inode. Fix: force-recreate the container after any `nginx.conf` change:
```bash
docker compose -f stack/nginx/nginx.yaml up -d --force-recreate
```
Changes to `conf.d/*.conf` files are picked up by `nginx -s reload` correctly (directory mount).

### SSL cert issues
```bash
# Verify cert files exist and are readable
ls -la data/letsencrypt/live/districtsolutions.ai/

# Check cert details and SANs
openssl x509 -in data/letsencrypt/live/districtsolutions.ai/cert.pem -text -noout | grep -E "Subject:|DNS:"

# Check cert expiry
openssl x509 -in data/letsencrypt/live/districtsolutions.ai/cert.pem -noout -enddate

# Force re-issue if needed
rm -rf data/letsencrypt/live/districtsolutions.ai
rm -rf data/letsencrypt/archive/districtsolutions.ai
rm -f data/letsencrypt/renewal/districtsolutions.ai.conf
./scripts/issue-cert.sh
```

### Can't reach Open WebUI through nginx
```bash
# Verify containers are on core-net
docker network inspect core-net | grep -A2 "biz-tool-oweb"

# Test connectivity from nginx container
docker exec core-nginx wget -qO- http://biz-tool-oweb:8080 | head -5
```

### Docker network issues
```bash
# Verify all containers are on core-net
docker network inspect core-net
# All service containers should be listed

# If a container is missing, reconnect it
docker network connect core-net <container-name>
```

### fail2ban shows "No file is currently monitored"
fail2ban may default to `backend = systemd` which reads the journal, ignoring `logpath`. Fix: verify `backend = auto` in each nginx jail in `jail.local`. Then `systemctl restart fail2ban`.

### API can't reach Postgres
```bash
# Check postgres is running and healthy
docker ps | grep postgres
docker exec biz-tool-postgres pg_isready -U biztool

# Check network connectivity
docker exec biz-tool-api python -c "import socket; socket.create_connection(('biz-tool-postgres', 5432)); print('ok')"
```

### Worker can't reach SQS
```bash
# Verify AWS credentials on EC2 (uses instance profile / IAM role)
docker exec biz-tool-worker python -c "import boto3; print(boto3.client('sts').get_caller_identity())"

# Check queue exists
aws sqs get-queue-url --queue-name biz-tool-prod-task-queue
```

### Open WebUI Authorization header conflicts
The nginx config for kb.districtsolutions.ai does NOT have basic auth enabled. This is intentional - OWU uses JWT tokens in the Authorization header. Adding nginx basic auth would intercept those tokens and break OWU.

### SSH from MacBook
```bash
ssh kevin@34.234.159.163
cd /opt/ds/core
```
