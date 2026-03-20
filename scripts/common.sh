#!/bin/bash
# common.sh - shared variables and helpers for all scripts
# Source this file: source "$(dirname "$0")/common.sh"

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

# ECR settings
AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID:-381492049589}"
AWS_REGION="${AWS_REGION:-us-east-1}"
ENV_NAME="${ENV_NAME:-prod}"
REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

# Target platform for ECR images (server is x86_64)
BUILD_PLATFORM="${BUILD_PLATFORM:-linux/amd64}"

ecr_login() {
    echo "=== logging in to ECR ==="
    aws ecr get-login-password --region "$AWS_REGION" | \
        docker login --username AWS --password-stdin "$REGISTRY"
}

ecr_image() {
    local service="$1"
    local tag="${2:-latest}"
    echo "${REGISTRY}/core/${ENV_NAME}/${service}:${tag}"
}

git_tag() {
    git -C "$ROOT_DIR" rev-parse --short HEAD 2>/dev/null || echo "latest"
}
