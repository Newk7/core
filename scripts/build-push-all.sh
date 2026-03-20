#!/bin/bash
# build-push-all.sh - build and push all custom images to ECR
# Usage: ./scripts/build-push-all.sh [service...]
# Examples:
#   ./scripts/build-push-all.sh          # build all
#   ./scripts/build-push-all.sh api      # build only api
#   ./scripts/build-push-all.sh api worker  # build api and worker
source "$(dirname "$0")/common.sh"

ALL_SERVICES=(api worker soc-worker soc-web district-web)

if [ $# -gt 0 ]; then
    SERVICES=("$@")
else
    SERVICES=("${ALL_SERVICES[@]}")
fi

for svc in "${SERVICES[@]}"; do
    echo ""
    echo "==============================="
    echo "  building $svc"
    echo "==============================="
    "$SCRIPT_DIR/build-push-${svc}.sh"
done

echo ""
echo "=== all done ==="
