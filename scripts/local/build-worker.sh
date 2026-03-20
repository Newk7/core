#!/bin/bash
# local/build-worker.sh - build the worker image locally
source "$(dirname "$0")/../common.sh"

echo "=== building worker (local) ==="
docker build -t worker -f "$ROOT_DIR/stack/worker/Dockerfile" "$ROOT_DIR"
echo "✓ worker built locally"
