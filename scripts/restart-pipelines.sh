#!/bin/bash
# restart-pipelines.sh - restart OpenWebUI Pipelines server
source "$(dirname "$0")/common.sh"

echo "--- restarting pipelines ---"
cd "$ROOT_DIR/stack/pipelines"
docker compose pull
docker compose down 2>/dev/null || true
docker compose up -d

echo "✓ pipelines restarted"
