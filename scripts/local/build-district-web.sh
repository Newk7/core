#!/bin/bash
# local/build-district-web.sh - build the district website image locally
source "$(dirname "$0")/../common.sh"

if [ -n "${DISTRICT_WEB_DIR:-}" ]; then
    true
elif [ -d "$ROOT_DIR/../districtsolutions" ]; then
    DISTRICT_WEB_DIR="$ROOT_DIR/../districtsolutions"
elif [ -d "$HOME/dir/districtsolutions" ]; then
    DISTRICT_WEB_DIR="$HOME/dir/districtsolutions"
else
    echo "ERROR: District web directory not found"
    echo "Set DISTRICT_WEB_DIR to point to the districtsolutions directory"
    exit 1
fi

echo "=== building district-web (local, from $DISTRICT_WEB_DIR) ==="
docker build -t district-web \
    -f "$DISTRICT_WEB_DIR/Dockerfile" \
    "$DISTRICT_WEB_DIR"
echo "✓ district-web built locally"
