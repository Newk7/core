#!/bin/bash
# build-push-district-web.sh - build and push the district website image to ECR
source "$(dirname "$0")/common.sh"

TAG="${IMAGE_TAG:-$(git_tag)}"
DISTRICT_WEB_DIR="${DISTRICT_WEB_DIR:-/opt/ds/districtsolutions}"

ecr_login

echo "=== building district-web (from $DISTRICT_WEB_DIR) ==="
docker build -t district-web \
    -f "$DISTRICT_WEB_DIR/Dockerfile" \
    "$DISTRICT_WEB_DIR"

echo "=== tagging ==="
docker tag district-web "$(ecr_image district-web "$TAG")"
docker tag district-web "$(ecr_image district-web latest)"

echo "=== pushing ==="
docker push "$(ecr_image district-web "$TAG")"
docker push "$(ecr_image district-web latest)"

echo "✓ district-web pushed → $(ecr_image district-web "$TAG")"
