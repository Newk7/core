#!/bin/bash
# restart-nginx.sh - restart nginx service
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

cd "$ROOT_DIR/stack/nginx"
docker compose -f nginx.yaml down 2>/dev/null || true
docker compose -f nginx.yaml up -d

echo "nginx restarted"
docker logs core-nginx --tail 5
