# Quick Reference

## Common Commands

```bash
# Start everything
./scripts/restart-all.sh

# Restart individual services
cd stack/db && docker compose -f db.yaml down && docker compose -f db.yaml up -d
docker compose -f stack/db/pg-admin.yaml --env-file .env up -d   # pgAdmin
cd stack/oweb && docker compose down && docker compose up -d
cd stack/api && docker compose down && docker compose up -d --build
cd stack/worker && docker compose down && docker compose up -d --build
cd stack/district-web && docker compose down && docker compose up -d --build
./scripts/restart-nginx.sh

# nginx reload vs force-recreate
# conf.d/*.conf changes  → nginx -s reload is sufficient (directory mount)
# nginx.conf changes     → must force-recreate (file bind mount, git pull changes inode)
docker exec core-nginx nginx -s reload
docker compose -f stack/nginx/nginx.yaml up -d --force-recreate  # after nginx.conf change

# Generate htpasswd (after changing password in .env)
./scripts/generate-htpasswd.sh

# Check all containers
docker ps

# View nginx logs
tail -f data/nginx/logs/kb.districtsolutions.ai_access.log
tail -f data/nginx/logs/api.districtsolutions.ai_error.log

# --- fail2ban ---
# Overview of all jails
sudo fail2ban-client status

# Check a specific jail (banned IPs, fail count)
sudo fail2ban-client status nginx-http-auth
sudo fail2ban-client status nginx-botsearch
sudo fail2ban-client status nginx-limit-req
sudo fail2ban-client status sshd

# Unban an IP from a specific jail
sudo fail2ban-client set nginx-http-auth unbanip <IP>
sudo fail2ban-client set nginx-botsearch unbanip <IP>

# Unban an IP from ALL jails at once
sudo fail2ban-client unban <IP>

# Unban everyone (careful)
sudo fail2ban-client unban --all

# List all currently banned IPs across all jails
sudo fail2ban-client banned

# Check what fail2ban is monitoring (should show log file paths)
sudo fail2ban-client get nginx-botsearch logpath

# Reload after editing jail.local
sudo cp stack/fail2ban/jail.local /etc/fail2ban/jail.local
sudo systemctl restart fail2ban

# Postgres CLI
docker exec -it biz-tool-postgres psql -U biztool -d biztool
# Then: SELECT * FROM tasks ORDER BY created_at DESC LIMIT 10;

# Check SQS queue depth
aws sqs get-queue-attributes \
  --queue-url $(aws sqs get-queue-url --queue-name biz-tool-prod-task-queue --query QueueUrl --output text) \
  --attribute-names ApproximateNumberOfMessages

# Check S3 bucket
aws s3 ls s3://biz-tool-prod-task-data/tasks/ --recursive | tail -20

# API health check
curl -s https://api.districtsolutions.ai/health -u kevin:PASS
```

## URLs

| Service | URL | Auth |
|---------|-----|------|
| Website | https://districtsolutions.ai | None (public) |
| Open WebUI | https://kbaas.districtsolutions.ai | OWU login (no nginx auth) |
| API | https://api.districtsolutions.ai | nginx basic auth |
| API Health | https://api.districtsolutions.ai/health | None (exempt) |
| AI-SOC | https://aisoc.districtsolutions.ai | nginx basic auth |
| pgAdmin | https://pg.districtsolutions.ai | nginx basic auth + pgAdmin login |
| Mattermost | https://msg.districtsolutions.ai | MM login (no nginx auth) |
| Gitea | https://git.districtsolutions.ai | nginx basic auth |
| Gitea SSH | `ssh://git@git.districtsolutions.ai:2222` | SSH key |

**pgAdmin connection details** (when adding server inside pgAdmin):
- Host: `biz-tool-postgres`
- Port: `5432`
- Database: `biztool`
- Username/Password: `POSTGRES_USER` / `POSTGRES_PASSWORD` from `.env`

## API Endpoints

```bash
# Health check (no auth)
curl https://api.districtsolutions.ai/health

# Create a task (auth required)
curl -u kevin:PASS -X POST https://api.districtsolutions.ai/api/v1/tasks \
  -H "Content-Type: application/json" \
  -d '{"type": "shred", "msg": "process document"}'

# Get task status
curl -u kevin:PASS https://api.districtsolutions.ai/api/v1/tasks/{task-id}

# List tasks
curl -u kevin:PASS "https://api.districtsolutions.ai/api/v1/tasks?limit=10"

# Upload file and create task
curl -u kevin:PASS -X POST https://api.districtsolutions.ai/api/v1/upload \
  -F "file=@document.pdf" \
  -F "task_type=shred"

# Submit contact form (no auth - public endpoint)
curl -X POST https://api.districtsolutions.ai/api/v1/contact \
  -H "Content-Type: application/json" \
  -d '{"name": "John Doe", "email": "john@co.com", "message": "Hello"}'
```

## CloudFormation Stacks

```bash
# Deploy / update stacks
aws cloudformation deploy --template-file stack/cf/build-host/host.yaml --stack-name AI-BizTool --capabilities CAPABILITY_NAMED_IAM
aws cloudformation deploy --template-file stack/cf/s3/s3.yaml --stack-name biz-tool-s3
aws cloudformation deploy --template-file stack/cf/sqs/sqs.yaml --stack-name biz-tool-sqs
aws cloudformation deploy --template-file stack/cf/ses/ses.yaml --stack-name biz-tool-ses --capabilities CAPABILITY_NAMED_IAM

# After SES deploy: add DKIM + MAIL FROM DNS records, then request production access
# Check SES domain verification status
aws ses get-email-identity --email-identity districtsolutions.ai --query 'DkimAttributes.Status'

# Check stack status
aws cloudformation describe-stacks --query 'Stacks[*].{Name:StackName,Status:StackStatus}' --output table
```

## SSH Access from MacBook

```bash
ssh kevin@34.234.159.163
cd /opt/ds/core
```

## Local Development

```bash
# Install package in dev mode
pip install -e ".[dev]"

# Run the API locally
ENV_NAME=dev uvicorn core.api.server:app --reload --port 8000

# Run the worker locally
ENV_NAME=dev python -m core.eng.worker

# Run tests
pytest

# --- District Solutions Website (separate repo) ---
cd /path/to/districtsolutions
npm install
npm run dev           # http://localhost:5173
npm run build         # Production build to dist/
npm test              # Playwright tests (6 viewports)
```

## Backup Strategy

Critical data to back up:
```
data/letsencrypt/      # SSL certificates (Let's Encrypt, auto-renewed)
data/nginx/logs/       # Nginx logs (for fail2ban and audit)
.env                   # Secrets (store separately/securely)
```

AWS-managed data (backed up by AWS):
```
S3 bucket              # Versioned, lifecycle rules
SQS queues             # Ephemeral (messages processed and deleted)
Postgres               # Docker volume on EC2 (consider RDS for production)
Open WebUI             # Docker volume (oweb-data)
```

## SSL Certificate (Let's Encrypt + Certbot)

Certs are free from Let's Encrypt, auto-renewed by certbot via cron. Expires every 90 days.

```bash
# Check current expiry
openssl x509 -in data/letsencrypt/live/districtsolutions.ai/cert.pem -noout -enddate

# Manual renewal (cron does this automatically)
./scripts/renew-cert.sh

# Force re-issue (if something went wrong)
./scripts/issue-cert.sh

# Verify cert is active on the server
openssl s_client -connect districtsolutions.ai:443 -servername districtsolutions.ai </dev/null 2>/dev/null | openssl x509 -noout -dates

# Cert files (managed by certbot, don't edit manually)
ls data/letsencrypt/live/districtsolutions.ai/
# fullchain.pem  privkey.pem  cert.pem  chain.pem
```

Auto-renewal cron (should already be set up — see Step 5f):
```cron
0 3 1,15 * * /opt/ds/core/scripts/renew-cert.sh >> /var/log/cert-renewal.log 2>&1
```
