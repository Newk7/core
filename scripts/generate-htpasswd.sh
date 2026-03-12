#!/bin/bash
# generate-htpasswd.sh - create htpasswd file for nginx basic auth
# requires: apache2-utils (apt) or httpd-tools (dnf)
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

if [ -f "$ROOT_DIR/.env" ]; then
    source "$ROOT_DIR/.env"
fi

HTPASSWD_USER="${HTPASSWD_USER:?HTPASSWD_USER not set}"
HTPASSWD_PASS="${HTPASSWD_PASS:?HTPASSWD_PASS not set}"

HTPASSWD_FILE="$ROOT_DIR/stack/nginx/htpasswd"

# try htpasswd (apache2-utils) or use openssl fallback
if command -v htpasswd &>/dev/null; then
    htpasswd -cb "$HTPASSWD_FILE" "$HTPASSWD_USER" "$HTPASSWD_PASS"
else
    # openssl fallback for systems without apache2-utils
    HASH=$(openssl passwd -apr1 "$HTPASSWD_PASS")
    echo "${HTPASSWD_USER}:${HASH}" > "$HTPASSWD_FILE"
fi

echo "htpasswd written to $HTPASSWD_FILE"
