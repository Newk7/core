#!/bin/bash
# local/up.sh - build and start all services locally (no ECR)
# This is the local development equivalent of restart-all.sh
source "$(dirname "$0")/../common.sh"

echo "=== local dev startup ==="

# create shared docker network if it doesn't exist
docker network inspect core-net >/dev/null 2>&1 || \
    docker network create core-net && echo "created core-net network"

# create data directories
mkdir -p "$ROOT_DIR/data/ssl"
mkdir -p "$ROOT_DIR/data/nginx/logs"
mkdir -p "$ROOT_DIR/data/oweb"
mkdir -p "$ROOT_DIR/data/pipelines"
mkdir -p "$ROOT_DIR/data/mattermost/data"
mkdir -p "$ROOT_DIR/data/mattermost/logs"
mkdir -p "$ROOT_DIR/data/mattermost/config"
mkdir -p "$ROOT_DIR/data/mattermost/plugins"
mkdir -p "$ROOT_DIR/data/mattermost/client-plugins"

# 1. postgres
echo "--- starting postgres ---"
cd "$ROOT_DIR/stack/db"
docker compose -f db.yaml down 2>/dev/null || true
docker compose -f db.yaml up -d
echo "waiting for postgres..."
sleep 5

# 2. pipelines
echo "--- starting pipelines ---"
cd "$ROOT_DIR/stack/pipelines"
docker compose down 2>/dev/null || true
docker compose up -d

# 3. open webui
echo "--- starting open webui ---"
cd "$ROOT_DIR/stack/oweb"
docker compose down 2>/dev/null || true
docker compose up -d

# 4. mattermost
echo "--- starting mattermost ---"
cd "$ROOT_DIR/stack/mattermost"
docker compose down 2>/dev/null || true
docker compose up -d

# 3-7. custom images — build locally
for svc in api worker soc-worker soc-web district-web; do
    echo "--- starting $svc (local build) ---"
    cd "$ROOT_DIR/stack/$svc"
    docker compose down 2>/dev/null || true
    docker compose up -d --build 2>/dev/null || echo "⚠ $svc build failed (check paths/deps)"
done

# 8. nginx
echo "--- starting nginx ---"
cd "$ROOT_DIR/stack/nginx"
docker compose -f nginx.yaml down 2>/dev/null || true
docker compose -f nginx.yaml up -d

echo ""
echo "=== all services started (local build mode) ==="
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
