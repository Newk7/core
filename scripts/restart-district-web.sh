#!/bin/bash
# restart-district-web.sh - pull latest image from ECR and restart the district website
source "$(dirname "$0")/common.sh"

ecr_login

echo "--- restarting district-web ---"
cd "$ROOT_DIR/stack/district-web"
docker compose pull
docker compose down 2>/dev/null || true
docker compose up -d

echo "✓ district-web restarted"
