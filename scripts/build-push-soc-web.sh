#!/bin/bash
# build-push-soc-web.sh - build and push the SOC web frontend image to ECR
source "$(dirname "$0")/common.sh"

TAG="${IMAGE_TAG:-$(git_tag)}"
# Resolve soc-web directory: env var > server path > local sibling repo
if [ -n "${SOC_WEB_DIR:-}" ]; then
    true
elif [ -d "/opt/ds/ai-soc/soc-agent/web" ]; then
    SOC_WEB_DIR="/opt/ds/ai-soc/soc-agent/web"
elif [ -d "$ROOT_DIR/../ai-soc/soc-agent/web" ]; then
    SOC_WEB_DIR="$ROOT_DIR/../ai-soc/soc-agent/web"
elif [ -d "$ROOT_DIR/../ai-soc/soc-agent 2/web" ]; then
    SOC_WEB_DIR="$ROOT_DIR/../ai-soc/soc-agent 2/web"
else
    echo "ERROR: SOC web directory not found"
    echo "Set SOC_WEB_DIR to point to the ai-soc web/ directory"
    exit 1
fi

ecr_login

echo "=== building soc-web (from $SOC_WEB_DIR) ==="
docker build --platform "$BUILD_PLATFORM" -t soc-web \
    -f "$ROOT_DIR/stack/soc-web/Dockerfile" \
    "$SOC_WEB_DIR"

echo "=== tagging ==="
docker tag soc-web "$(ecr_image soc-web "$TAG")"
docker tag soc-web "$(ecr_image soc-web latest)"

echo "=== pushing ==="
docker push "$(ecr_image soc-web "$TAG")"
docker push "$(ecr_image soc-web latest)"

echo "✓ soc-web pushed → $(ecr_image soc-web "$TAG")"
