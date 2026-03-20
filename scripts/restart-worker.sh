#!/bin/bash
# restart-worker.sh - pull latest image from ECR and restart the worker
source "$(dirname "$0")/common.sh"

ecr_login

echo "--- restarting worker ---"
cd "$ROOT_DIR/stack/worker"
docker compose pull
docker compose down 2>/dev/null || true
docker compose up -d

echo "✓ worker restarted"
