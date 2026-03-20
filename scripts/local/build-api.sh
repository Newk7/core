#!/bin/bash
# local/build-api.sh - build the API image locally
source "$(dirname "$0")/../common.sh"

echo "=== building api (local) ==="
docker build -t api -f "$ROOT_DIR/stack/api/Dockerfile" "$ROOT_DIR"
echo "✓ api built locally"
