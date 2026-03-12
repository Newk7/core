#!/bin/bash
# setup-fail2ban.sh - install and configure fail2ban on EC2 host
# run as root or with sudo
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

echo "=== setting up fail2ban ==="

# install
if command -v dnf &>/dev/null; then
    dnf install -y fail2ban
elif command -v apt-get &>/dev/null; then
    apt-get update && apt-get install -y fail2ban
fi

# copy configs
cp "$ROOT_DIR/stack/fail2ban/jail.local" /etc/fail2ban/jail.local
cp "$ROOT_DIR/stack/fail2ban/filter.d/nginx-auth.conf" /etc/fail2ban/filter.d/nginx-auth.conf
cp "$ROOT_DIR/stack/fail2ban/filter.d/nginx-botsearch.conf" /etc/fail2ban/filter.d/nginx-botsearch.conf

# enable and start
systemctl enable fail2ban
systemctl restart fail2ban

echo "=== fail2ban status ==="
fail2ban-client status
