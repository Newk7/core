#!/bin/bash
# restart-api.sh - pull latest image from ECR and restart the API
source "$(dirname "$0")/common.sh"

ecr_login

echo "--- restarting api ---"
cd "$ROOT_DIR/stack/api"
docker compose pull
docker compose down 2>/dev/null || true
docker compose up -d

echo "✓ api restarted"
