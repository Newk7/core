#!/bin/bash
# local/build-all.sh - build all (or specific) images locally without pushing to ECR
# Usage: ./scripts/local/build-all.sh          # build all
#        ./scripts/local/build-all.sh api       # build only api
#        ./scripts/local/build-all.sh api worker # build api and worker
source "$(dirname "$0")/../common.sh"

ALL_SERVICES=(api worker soc-worker soc-web district-web)

if [ $# -gt 0 ]; then
    SERVICES=("$@")
else
    SERVICES=("${ALL_SERVICES[@]}")
fi

for svc in "${SERVICES[@]}"; do
    echo ""
    echo "==============================="
    echo "  building $svc (local)"
    echo "==============================="
    "$SCRIPT_DIR/local/build-${svc}.sh"
done

echo ""
echo "=== all local builds done ==="
docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}" | grep -E "^(api|worker|soc-|district-)" || true
