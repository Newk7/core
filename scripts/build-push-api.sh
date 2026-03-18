#!/bin/bash
# push-api.sh - build and push the core API image to ECR
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID:-381492049589}"
AWS_REGION="${AWS_REGION:-us-east-1}"
ENV_NAME="${ENV_NAME:-prod}"
REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
REPO="core/${ENV_NAME}/api"
TAG="${IMAGE_TAG:-$(git -C "$ROOT_DIR" rev-parse --short HEAD 2>/dev/null || echo 'latest')}"

echo "=== logging in to ECR ==="
aws ecr get-login-password --region "$AWS_REGION" | \
    docker login --username AWS --password-stdin "$REGISTRY"

echo "=== building api ==="
docker build -t api -f "$ROOT_DIR/stack/api/Dockerfile" "$ROOT_DIR"

echo "=== tagging ==="
docker tag api "$REGISTRY/$REPO:$TAG"
docker tag api "$REGISTRY/$REPO:latest"

echo "=== pushing ==="
docker push "$REGISTRY/$REPO:$TAG"
docker push "$REGISTRY/$REPO:latest"

echo "✓ api pushed → $REGISTRY/$REPO:$TAG"
