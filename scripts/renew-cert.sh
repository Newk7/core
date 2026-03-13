#!/bin/bash
# renew-cert.sh - Renew Let's Encrypt SSL cert and reload nginx
# Run from repo root: ./scripts/renew-cert.sh
# Add to cron for auto-renewal (certs expire every 90 days):
#   0 3 1,15 * * /home/ec2-user/core/scripts/renew-cert.sh >> /var/log/cert-renewal.log 2>&1

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

# Load env
if [ -f "$ROOT_DIR/.env" ]; then
    set -a; source "$ROOT_DIR/.env"; set +a
fi

: "${DOMAIN:?Set DOMAIN in .env}"

echo "$(date) - Starting cert renewal for $DOMAIN"

mkdir -p "$ROOT_DIR/data/certbot-webroot"

# Run certbot renew (only renews if cert is within 30 days of expiry)
docker run --rm \
    -v "$ROOT_DIR/data/letsencrypt:/etc/letsencrypt" \
    -v "$ROOT_DIR/data/certbot-webroot:/var/www/certbot" \
    certbot/certbot:latest \
    renew --quiet

# Reload nginx to pick up renewed cert (no downtime)
docker exec core-nginx nginx -s reload 2>/dev/null && \
    echo "$(date) - nginx reloaded" || \
    echo "$(date) - WARNING: nginx reload failed (is it running?)"

echo "$(date) - Renewal check complete"
