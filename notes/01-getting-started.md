# Getting Started - District Solutions AI Infrastructure

## Machine Profile

| Component | Value |
|-----------|-------|
| Host | AWS EC2 t3.medium (Amazon Linux 2023) |
| Region | us-east-1 |
| VPC | vpc-0dd28884da7e4d4eb (10.0.0.0/16) |
| Subnet | subnet-0531a7a14eef69db2 (10.0.0.0/24, us-east-1b, public) |
| Public IP | 34.234.159.163 |
| Domain | districtsolutions.ai (DNS provider, purchased cert) |
| Python | 3.11 (container) |
| Account | 381492049589 |

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

### Step 2: SSH into EC2 and Clone the Repo

```bash
ssh ec2-user@34.234.159.163

# Clone the repo
cd /home/ec2-user
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
| A | `kb` | 34.234.159.163 | 1800 |
| A | `api` | 34.234.159.163 | 1800 |

**Verify:**
```bash
dig districtsolutions.ai
dig kb.districtsolutions.ai
dig api.districtsolutions.ai
# All should return 34.234.159.163
```

---

### Step 5: Install SSL Certificate

You purchased a cert through your DNS provider. Place the cert files on the EC2 host:

```bash
mkdir -p /home/ec2-user/core/data/ssl

# Copy your cert files (from your local machine)
scp districtsolutions.ai.crt ec2-user@34.234.159.163:/home/ec2-user/core/data/ssl/
scp districtsolutions.ai.key ec2-user@34.234.159.163:/home/ec2-user/core/data/ssl/
```

**If your provider gave you separate cert + CA bundle files:**
```bash
# Concatenate into a single fullchain file
cat districtsolutions.ai.crt ca-bundle.crt > data/ssl/districtsolutions.ai.crt
```

**Verify the cert:**
```bash
openssl x509 -in data/ssl/districtsolutions.ai.crt -text -noout | grep -E "Subject:|DNS:|Issuer:"
# Should show your domain and the CA that issued it

# Verify key matches cert
openssl x509 -noout -modulus -in data/ssl/districtsolutions.ai.crt | md5sum
openssl rsa -noout -modulus -in data/ssl/districtsolutions.ai.key | md5sum
# Both md5sums must match
```

**Set permissions:**
```bash
chmod 600 data/ssl/districtsolutions.ai.key
chmod 644 data/ssl/districtsolutions.ai.crt
```

---

### Step 6: Create Docker Network and Generate htpasswd

```bash
cd /home/ec2-user/core

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
The docker-compose at `stack/district-web/` references the source at `../../frontend/district-web`.

```bash
mkdir -p /home/ec2-user/frontend
cd /home/ec2-user/frontend
git clone <district-solutions-git-remote> district-web
```

Expected directory layout on EC2:
```
/home/ec2-user/
  core/                    # This repo (infra, API, worker)
  frontend/
    district-web/          # District Solutions website (React SPA)
```

---

### Step 8: Start All Services

```bash
cd /home/ec2-user/core
./scripts/restart-all.sh
```

This starts in order: postgres → open-webui → api → worker → district-web → nginx

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

**Test fail2ban** (from another machine):
```bash
# Make 6 failed auth attempts (exceeds maxretry=5)
for i in {1..6}; do curl -sk -u wrong:wrong https://api.districtsolutions.ai; done

# Check if the IP got banned (on EC2)
sudo fail2ban-client status nginx-http-auth
# Should show the client's IP in the banned list

# Unban yourself if needed
sudo fail2ban-client set nginx-http-auth unbanip <your-ip>
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

Expected (pre-launch):
| Port | CIDR | Purpose |
|------|------|---------|
| 22 | your-ip/32 | SSH access |
| 80 | your-ip/32 | HTTP (CIDR-locked until go-live) |
| 443 | your-ip/32 | HTTPS (CIDR-locked until go-live) |

> **Note:** The CloudFormation template (`stack/cf/build-host/host.yaml`) uses `IngressCIDR` and `IngressCIDR1` parameters to lock all ports to specific IPs. This keeps the site, API, and all services inaccessible to the public until go-live.

---

### Step 13: Go-Live Checklist

When ready to make the site publicly accessible:

1. **Open ports 80 and 443 to the public** by updating the security group. Either:
   - Update the CloudFormation template to use `0.0.0.0/0` for HTTP/HTTPS rules (keep SSH CIDR-locked), then redeploy:
     ```bash
     aws cloudformation deploy \
       --template-file stack/cf/build-host/host.yaml \
       --stack-name AI-BizTool \
       --capabilities CAPABILITY_NAMED_IAM \
       --region us-east-1
     ```
   - Or update the security group directly in the AWS console (faster, but drifts from CF template).

2. **Verify public access** from a non-whitelisted IP (e.g., mobile hotspot):
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

### SSL cert issues
```bash
# Verify cert files exist and are readable
ls -la data/ssl/
openssl x509 -in data/ssl/districtsolutions.ai.crt -text -noout | head -20

# Verify key matches cert
openssl x509 -noout -modulus -in data/ssl/districtsolutions.ai.crt | md5sum
openssl rsa -noout -modulus -in data/ssl/districtsolutions.ai.key | md5sum
# Must match

# Check cert expiry
openssl x509 -in data/ssl/districtsolutions.ai.crt -noout -enddate
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
ssh ec2-user@34.234.159.163
cd /home/ec2-user/core
```
