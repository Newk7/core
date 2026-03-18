#!/bin/bash
# push-soc-worker.sh - build and push the SOC worker image to ECR
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID:-381492049589}"
AWS_REGION="${AWS_REGION:-us-east-1}"
ENV_NAME="${ENV_NAME:-prod}"
REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
REPO="core/${ENV_NAME}/soc-worker"
TAG="${IMAGE_TAG:-$(git -C "$ROOT_DIR" rev-parse --short HEAD 2>/dev/null || echo 'latest')}"

echo "=== logging in to ECR ==="
aws ecr get-login-password --region "$AWS_REGION" | \
    docker login --username AWS --password-stdin "$REGISTRY"

echo "=== building soc-worker ==="
docker build -t soc-worker -f "$ROOT_DIR/stack/soc-worker/Dockerfile" "$ROOT_DIR"

echo "=== tagging ==="
docker tag soc-worker "$REGISTRY/$REPO:$TAG"
docker tag soc-worker "$REGISTRY/$REPO:latest"

echo "=== pushing ==="
docker push "$REGISTRY/$REPO:$TAG"
docker push "$REGISTRY/$REPO:latest"

echo "✓ soc-worker pushed → $REGISTRY/$REPO:$TAG"
