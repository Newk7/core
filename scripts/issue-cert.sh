#!/bin/bash
# issue-cert.sh - Issue Let's Encrypt SSL cert via HTTP-01 challenge
# Prerequisites:
#   1. Port 80 must be open to the internet (SG rule 0.0.0.0/0 or at least Let's Encrypt IPs)
#   2. nginx must be running and serving /.well-known/acme-challenge/
#   3. DNS A records for districtsolutions.ai, api.districtsolutions.ai,
#      kbaas.districtsolutions.ai, pg.districtsolutions.ai, aisoc.districtsolutions.ai,
#      msg.districtsolutions.ai, git.districtsolutions.ai must point to this server
#
# Run from repo root: ./scripts/issue-cert.sh

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

# Load env
if [ -f "$ROOT_DIR/.env" ]; then
    set -a; source "$ROOT_DIR/.env"; set +a
fi

# Ensure ADMIN_EMAIL and DOMAIN are set
: "${ADMIN_EMAIL:?Set ADMIN_EMAIL in .env (e.g. hello@districtsolutions.ai)}"
: "${DOMAIN:?Set DOMAIN in .env (e.g. districtsolutions.ai)}"

# Create webroot directory
mkdir -p "$ROOT_DIR/data/certbot-webroot"
mkdir -p "$ROOT_DIR/data/letsencrypt"

echo "=== Issuing Let's Encrypt cert for $DOMAIN ==="
echo "Make sure port 80 is open to the internet and nginx is running."
echo ""

cd "$ROOT_DIR/stack/certbot"
docker compose -f certbot.yaml run --rm certbot

echo ""
echo "=== Done ==="
echo "Cert files at: data/letsencrypt/live/$DOMAIN/"
echo "  fullchain.pem  (cert + chain — use for ssl_certificate)"
echo "  privkey.pem    (private key — use for ssl_certificate_key)"
echo ""
echo "Restart nginx to pick up the new cert:"
echo "  ./scripts/restart-nginx.sh"
