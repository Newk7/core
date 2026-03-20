#!/bin/bash
# build-push-soc-web.sh - build and push the SOC web frontend image to ECR
source "$(dirname "$0")/common.sh"

TAG="${IMAGE_TAG:-$(git_tag)}"
SOC_WEB_DIR="${SOC_WEB_DIR:-/opt/ds/ai-soc/soc-agent/web}"

ecr_login

echo "=== building soc-web (from $SOC_WEB_DIR) ==="
docker build -t soc-web \
    -f "$ROOT_DIR/stack/soc-web/Dockerfile" \
    "$SOC_WEB_DIR"

echo "=== tagging ==="
docker tag soc-web "$(ecr_image soc-web "$TAG")"
docker tag soc-web "$(ecr_image soc-web latest)"

echo "=== pushing ==="
docker push "$(ecr_image soc-web "$TAG")"
docker push "$(ecr_image soc-web latest)"

echo "✓ soc-web pushed → $(ecr_image soc-web "$TAG")"
