#!/bin/bash
# docker-prune.sh - clean up old Docker images to reclaim disk space
# Safe: only removes dangling images and unused build cache
source "$(dirname "$0")/common.sh"

echo "=== Docker disk usage before cleanup ==="
docker system df

echo ""
echo "=== removing dangling images ==="
docker image prune -f

echo ""
echo "=== removing unused build cache ==="
docker builder prune -f

echo ""
echo "=== Docker disk usage after cleanup ==="
docker system df
