#!/bin/bash
# restart-oweb.sh - restart Open WebUI
source "$(dirname "$0")/common.sh"

echo "--- restarting open webui ---"
cd "$ROOT_DIR/stack/oweb"
docker compose pull
docker compose down 2>/dev/null || true
docker compose up -d

echo "✓ open webui restarted"
