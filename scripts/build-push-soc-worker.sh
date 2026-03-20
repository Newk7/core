#!/bin/bash
# build-push-soc-worker.sh - build and push the SOC worker image to ECR
source "$(dirname "$0")/common.sh"

TAG="${IMAGE_TAG:-$(git_tag)}"

ecr_login

echo "=== building soc-worker ==="
docker build --platform "$BUILD_PLATFORM" -t soc-worker -f "$ROOT_DIR/stack/soc-worker/Dockerfile" "$ROOT_DIR"

echo "=== tagging ==="
docker tag soc-worker "$(ecr_image soc-worker "$TAG")"
docker tag soc-worker "$(ecr_image soc-worker latest)"

echo "=== pushing ==="
docker push "$(ecr_image soc-worker "$TAG")"
docker push "$(ecr_image soc-worker latest)"

echo "✓ soc-worker pushed → $(ecr_image soc-worker "$TAG")"
