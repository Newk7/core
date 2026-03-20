#!/bin/bash
# docker-prune.sh - clean up Docker images to reclaim disk space
# Usage:
#   ./scripts/docker-prune.sh          # safe: dangling images + build cache
#   ./scripts/docker-prune.sh --all    # aggressive: all unused images, volumes, build cache
source "$(dirname "$0")/common.sh"

echo "=== Docker disk usage before cleanup ==="
docker system df

if [ "${1:-}" = "--all" ]; then
    echo ""
    echo "=== removing all unused images, containers, networks, volumes, and build cache ==="
    docker system prune -a --volumes -f
else
    echo ""
    echo "=== removing dangling images ==="
    docker image prune -f

    echo ""
    echo "=== removing unused images (not used by any container) ==="
    docker image prune -a -f

    echo ""
    echo "=== removing unused build cache ==="
    docker builder prune -a -f

    echo ""
    echo "=== removing unused volumes ==="
    docker volume prune -f
fi

echo ""
echo "=== Docker disk usage after cleanup ==="
docker system df
