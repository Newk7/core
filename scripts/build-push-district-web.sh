#!/bin/bash
# build-push-district-web.sh - build and push the district website image to ECR
source "$(dirname "$0")/common.sh"

TAG="${IMAGE_TAG:-$(git_tag)}"
# Resolve district-web directory: env var > server path > local sibling repo
if [ -n "${DISTRICT_WEB_DIR:-}" ]; then
    true
elif [ -d "/opt/ds/districtsolutions" ]; then
    DISTRICT_WEB_DIR="/opt/ds/districtsolutions"
elif [ -d "$ROOT_DIR/../districtsolutions" ]; then
    DISTRICT_WEB_DIR="$ROOT_DIR/../districtsolutions"
else
    echo "ERROR: District web directory not found"
    echo "Set DISTRICT_WEB_DIR to point to the districtsolutions directory"
    exit 1
fi

ecr_login

echo "=== building district-web (from $DISTRICT_WEB_DIR) ==="
docker build --platform "$BUILD_PLATFORM" -t district-web \
    -f "$DISTRICT_WEB_DIR/Dockerfile" \
    "$DISTRICT_WEB_DIR"

echo "=== tagging ==="
docker tag district-web "$(ecr_image district-web "$TAG")"
docker tag district-web "$(ecr_image district-web latest)"

echo "=== pushing ==="
docker push "$(ecr_image district-web "$TAG")"
docker push "$(ecr_image district-web latest)"

echo "✓ district-web pushed → $(ecr_image district-web "$TAG")"
