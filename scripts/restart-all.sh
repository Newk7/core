#!/bin/bash
# restart-all.sh - pull latest images from ECR and start all core services in order
# Usage: ./scripts/restart-all.sh [--build]
#   --build  Build locally instead of pulling from ECR (fallback)
source "$(dirname "$0")/common.sh"

BUILD_MODE=false
if [ "${1:-}" = "--build" ]; then
    BUILD_MODE=true
    echo "=== core restart-all (local build mode) ==="
else
    echo "=== core restart-all (ECR pull mode) ==="
    ecr_login
fi

# create shared docker network if it doesn't exist
docker network inspect core-net >/dev/null 2>&1 || \
    docker network create core-net && echo "created core-net network"

# create data directories
mkdir -p "$ROOT_DIR/data/ssl"
mkdir -p "$ROOT_DIR/data/nginx/logs"
mkdir -p "$ROOT_DIR/data/oweb"

# helper: restart a compose service
restart_service() {
    local dir="$1"
    local compose_file="${2:-docker-compose.yaml}"
    local name="$(basename "$dir")"

    echo "--- starting $name ---"
    cd "$ROOT_DIR/stack/$dir"

    if [ "$compose_file" != "docker-compose.yaml" ]; then
        docker compose -f "$compose_file" down 2>/dev/null || true
        if [ "$BUILD_MODE" = true ]; then
            docker compose -f "$compose_file" up -d --build
        else
            docker compose -f "$compose_file" pull 2>/dev/null || true
            docker compose -f "$compose_file" up -d
        fi
    else
        docker compose down 2>/dev/null || true
        if [ "$BUILD_MODE" = true ]; then
            docker compose up -d --build
        else
            docker compose pull 2>/dev/null || true
            docker compose up -d
        fi
    fi
}

# 1. postgres
restart_service db db.yaml
echo "waiting for postgres..."
sleep 5

# 2. open webui
restart_service oweb

# 3. api
restart_service api

# 4. worker
restart_service worker

# 5. soc worker
restart_service soc-worker

# 6. soc web
restart_service soc-web

# 7. district web
restart_service district-web

# 8. nginx (last - needs backends to be up)
echo "--- starting nginx ---"
cd "$ROOT_DIR/stack/nginx"
docker compose -f nginx.yaml down 2>/dev/null || true
docker compose -f nginx.yaml up -d

echo ""
echo "=== all services started ==="
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
