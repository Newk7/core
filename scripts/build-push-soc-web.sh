#!/bin/bash
# push-soc-web.sh - build and push the SOC web frontend image to ECR
set -euo pipefail

AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID:-381492049589}"
AWS_REGION="${AWS_REGION:-us-east-1}"
ENV_NAME="${ENV_NAME:-prod}"
REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
REPO="core/${ENV_NAME}/soc-web"
TAG="${IMAGE_TAG:-latest}"

echo "=== logging in to ECR ==="
aws ecr get-login-password --region "$AWS_REGION" | \
    docker login --username AWS --password-stdin "$REGISTRY"

echo "=== building soc-web ==="
docker build -t soc-web \
    -f /opt/ds/core/stack/soc-web/Dockerfile \
    "/opt/ds/ai-soc/soc-agent 2"

echo "=== tagging ==="
docker tag soc-web "$REGISTRY/$REPO:$TAG"
docker tag soc-web "$REGISTRY/$REPO:latest"

echo "=== pushing ==="
docker push "$REGISTRY/$REPO:$TAG"
docker push "$REGISTRY/$REPO:latest"

echo "✓ soc-web pushed → $REGISTRY/$REPO:$TAG"
