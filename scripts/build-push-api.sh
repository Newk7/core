#!/bin/bash
# build-push-api.sh - build and push the core API image to ECR
source "$(dirname "$0")/common.sh"

TAG="${IMAGE_TAG:-$(git_tag)}"

ecr_login

echo "=== building api ==="
docker build -t api -f "$ROOT_DIR/stack/api/Dockerfile" "$ROOT_DIR"

echo "=== tagging ==="
docker tag api "$(ecr_image api "$TAG")"
docker tag api "$(ecr_image api latest)"

echo "=== pushing ==="
docker push "$(ecr_image api "$TAG")"
docker push "$(ecr_image api latest)"

echo "✓ api pushed → $(ecr_image api "$TAG")"
