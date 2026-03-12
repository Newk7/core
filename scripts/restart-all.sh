#!/bin/bash
# restart-all.sh - start all core services in order
# run from the repo root: ./scripts/restart-all.sh

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

echo "=== core restart-all ==="

# create shared docker network if it doesn't exist
docker network inspect core-net >/dev/null 2>&1 || \
    docker network create core-net && echo "created core-net network"

# create data directories
mkdir -p "$ROOT_DIR/data/ssl"
mkdir -p "$ROOT_DIR/data/nginx/logs"
mkdir -p "$ROOT_DIR/data/oweb"

# 1. postgres
echo "--- starting postgres ---"
cd "$ROOT_DIR/stack/db"
docker compose -f db.yaml down 2>/dev/null || true
docker compose -f db.yaml up -d

# wait for postgres to be ready
echo "waiting for postgres..."
sleep 5

# 2. open webui
echo "--- starting open webui ---"
cd "$ROOT_DIR/stack/oweb"
docker compose down 2>/dev/null || true
docker compose up -d

# 3. api
echo "--- starting api ---"
cd "$ROOT_DIR/stack/api"
docker compose down 2>/dev/null || true
docker compose up -d --build

# 4. worker
echo "--- starting worker ---"
cd "$ROOT_DIR/stack/worker"
docker compose down 2>/dev/null || true
docker compose up -d --build

# 5. nginx (last - needs backends to be up)
echo "--- starting nginx ---"
cd "$ROOT_DIR/stack/nginx"
docker compose -f nginx.yaml down 2>/dev/null || true
docker compose -f nginx.yaml up -d

echo "=== all services started ==="
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
