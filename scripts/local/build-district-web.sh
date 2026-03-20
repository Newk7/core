#!/bin/bash
# local/build-district-web.sh - build the district website image locally
source "$(dirname "$0")/../common.sh"

DISTRICT_WEB_DIR="${DISTRICT_WEB_DIR:-$ROOT_DIR/../districtsolutions}"

if [ ! -d "$DISTRICT_WEB_DIR" ]; then
    echo "ERROR: District web directory not found at $DISTRICT_WEB_DIR"
    echo "Set DISTRICT_WEB_DIR to point to the districtsolutions directory"
    exit 1
fi

echo "=== building district-web (local, from $DISTRICT_WEB_DIR) ==="
docker build -t district-web \
    -f "$DISTRICT_WEB_DIR/Dockerfile" \
    "$DISTRICT_WEB_DIR"
echo "✓ district-web built locally"
