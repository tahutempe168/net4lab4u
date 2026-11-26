#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPTS="${REPO_ROOT}/deploy/scripts"

bash "${SCRIPTS}/publish-acr-images.sh" --check
docker build -t nova-ve/backend:latest "${REPO_ROOT}/backend"
docker build -t nova-ve/frontend:latest "${REPO_ROOT}/frontend"
docker build -t nova-ve/ubuntu-2604-xfce-vnc:latest \
  "${REPO_ROOT}/deploy/demo-images/ubuntu-2604-xfce-vnc"

# Defer all publication until every build and runtime pull has succeeded.
NOVA_VE_ACR_REGISTRY= NOVA_VE_SKIP_DEMO_IMAGES=0 \
  bash "${SCRIPTS}/build-demo-images.sh"
NOVA_VE_ACR_REGISTRY= NOVA_VE_SKIP_PLATFORM_IMAGES=0 \
  NOVA_VE_PLATFORM_MODE=build NOVA_VE_PLATFORM_PULL=0 GHCR_PUSH=0 \
  bash "${SCRIPTS}/build-platform-images.sh"

for image in alpine:3.21 postgres:16-alpine postgres:16 \
  guacamole/guacd:latest guacamole/guacamole:latest; do
  docker pull "$image"
done

bash "${SCRIPTS}/publish-acr-images.sh"
