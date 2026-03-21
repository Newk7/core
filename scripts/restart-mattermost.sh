#!/bin/bash
# restart-mattermost.sh - restart Mattermost
source "$(dirname "$0")/common.sh"

# create data directories
mkdir -p "$ROOT_DIR/data/mattermost/data"
mkdir -p "$ROOT_DIR/data/mattermost/logs"
mkdir -p "$ROOT_DIR/data/mattermost/config"
mkdir -p "$ROOT_DIR/data/mattermost/plugins"
mkdir -p "$ROOT_DIR/data/mattermost/client-plugins"

echo "--- restarting mattermost ---"
cd "$ROOT_DIR/stack/mattermost"
docker compose pull
docker compose down 2>/dev/null || true
docker compose up -d

echo "✓ mattermost restarted"
