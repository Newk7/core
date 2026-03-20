#!/bin/bash
# restart-soc-worker.sh - pull latest image from ECR and restart the SOC worker
source "$(dirname "$0")/common.sh"

ecr_login

echo "--- restarting soc-worker ---"
cd "$ROOT_DIR/stack/soc-worker"
docker compose pull
docker compose down 2>/dev/null || true
docker compose up -d

echo "✓ soc-worker restarted"
