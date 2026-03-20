#!/bin/bash
# local/build-soc-web.sh - build the SOC web frontend image locally
source "$(dirname "$0")/../common.sh"

# Try common local paths for the ai-soc web directory
if [ -n "${SOC_WEB_DIR:-}" ]; then
    true  # use explicit env var
elif [ -d "$ROOT_DIR/../ai-soc/soc-agent/web" ]; then
    SOC_WEB_DIR="$ROOT_DIR/../ai-soc/soc-agent/web"
elif [ -d "$ROOT_DIR/../ai-soc/soc-agent 2/web" ]; then
    SOC_WEB_DIR="$ROOT_DIR/../ai-soc/soc-agent 2/web"
else
    echo "ERROR: SOC web directory not found"
    echo "Set SOC_WEB_DIR to point to the ai-soc web/ directory"
    echo "  e.g. export SOC_WEB_DIR=/path/to/ai-soc/soc-agent/web"
    exit 1
fi

echo "=== building soc-web (local, from $SOC_WEB_DIR) ==="
docker build -t soc-web \
    -f "$ROOT_DIR/stack/soc-web/Dockerfile" \
    "$SOC_WEB_DIR"
echo "✓ soc-web built locally"
