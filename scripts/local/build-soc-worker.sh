#!/bin/bash
# local/build-soc-worker.sh - build the SOC worker image locally
source "$(dirname "$0")/../common.sh"

echo "=== building soc-worker (local) ==="
docker build -t soc-worker -f "$ROOT_DIR/stack/soc-worker/Dockerfile" "$ROOT_DIR"
echo "✓ soc-worker built locally"
