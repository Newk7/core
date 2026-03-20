#!/bin/bash
# restart-soc-web.sh - pull latest image from ECR and restart the SOC web frontend
source "$(dirname "$0")/common.sh"

ecr_login

echo "--- restarting soc-web ---"
cd "$ROOT_DIR/stack/soc-web"
docker compose pull
docker compose down 2>/dev/null || true
docker compose up -d

echo "✓ soc-web restarted"
