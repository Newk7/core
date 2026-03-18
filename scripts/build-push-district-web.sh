#!/bin/bash
# push-district-web.sh - build and push the district website image to ECR
set -euo pipefail

AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID:-381492049589}"
AWS_REGION="${AWS_REGION:-us-east-1}"
ENV_NAME="${ENV_NAME:-prod}"
REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
REPO="core/${ENV_NAME}/district-web"
TAG="${IMAGE_TAG:-latest}"

echo "=== logging in to ECR ==="
aws ecr get-login-password --region "$AWS_REGION" | \
    docker login --username AWS --password-stdin "$REGISTRY"

echo "=== building district-web ==="
docker build -t district-web \
    -f /opt/ds/districtsolutions/Dockerfile \
    /opt/ds/districtsolutions

echo "=== tagging ==="
docker tag district-web "$REGISTRY/$REPO:$TAG"
docker tag district-web "$REGISTRY/$REPO:latest"

echo "=== pushing ==="
docker push "$REGISTRY/$REPO:$TAG"
docker push "$REGISTRY/$REPO:latest"

echo "✓ district-web pushed → $REGISTRY/$REPO:$TAG"
