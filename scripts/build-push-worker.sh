#!/bin/bash
# build-push-worker.sh - build and push the core worker image to ECR
source "$(dirname "$0")/common.sh"

TAG="${IMAGE_TAG:-$(git_tag)}"

ecr_login

echo "=== building worker ==="
docker build -t worker -f "$ROOT_DIR/stack/worker/Dockerfile" "$ROOT_DIR"

echo "=== tagging ==="
docker tag worker "$(ecr_image worker "$TAG")"
docker tag worker "$(ecr_image worker latest)"

echo "=== pushing ==="
docker push "$(ecr_image worker "$TAG")"
docker push "$(ecr_image worker latest)"

echo "✓ worker pushed → $(ecr_image worker "$TAG")"
