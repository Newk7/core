#!/bin/bash
# restart-db.sh - restart the postgres database
source "$(dirname "$0")/common.sh"

echo "--- restarting postgres ---"
cd "$ROOT_DIR/stack/db"
docker compose -f db.yaml down 2>/dev/null || true
docker compose -f db.yaml up -d

echo "waiting for postgres..."
sleep 5

echo "✓ postgres restarted"
