#!/usr/bin/env bash
set -euo pipefail

REGISTRY="${NOVA_VE_ACR_REGISTRY:-}"
if [[ -z "$REGISTRY" ]]; then
  echo "publish-acr-images: NOVA_VE_ACR_REGISTRY unset; skipping publication." >&2
  exit 0
fi
if [[ ! "$REGISTRY" =~ ^[a-z0-9][a-z0-9-]*\.azurecr\.(io|cn|us|de)$ ]]; then
  echo "publish-acr-images: use an ACR login server hostname, without a scheme, path or credentials." >&2
  exit 2
fi
if [[ "${1:-}" == "--check" ]]; then
  exit 0
fi

# Distinct runtime variants must not overwrite each other's latest tag.
IMAGES=(
  "nova-ve/backend:latest"
  "nova-ve/frontend:latest"
  "nova-ve/mgmt-server:latest"
  "nova-ve/browser:latest"
  "nova-ve/desktop:latest"
  "nova-ve/alpine-telnet:latest"
  "nova-ve/alpine-vnc:latest"
  "nova-ve/ubuntu-2604-xfce-vnc:latest"
  "alpine:3.22|nova-ve/runtime/alpine"
  "alpine:3.21|nova-ve/runtime/alpine-sandbox"
  "postgres:16-alpine|nova-ve/runtime/postgres-alpine"
  "postgres:16|nova-ve/runtime/postgres"
  "guacamole/guacd:latest"
  "guacamole/guacamole:latest"
)
if (( $# )); then
  IMAGES=("$@")
fi

SOURCES=()
TARGETS=()
for image in "${IMAGES[@]}"; do
  source="${image%%|*}"
  if [[ "$image" == *"|"* ]]; then
    repository="${image#*|}"
  else
    repository="${source%:*}"
  fi
  if [[ ! "$repository" =~ ^[a-z0-9]+([._-][a-z0-9]+)*(/[a-z0-9]+([._-][a-z0-9]+)*)*$ ]]; then
    echo "publish-acr-images: invalid destination repository '${repository}'." >&2
    exit 2
  fi
  docker image inspect "$source" >/dev/null
  SOURCES+=("$source")
  TARGETS+=("${REGISTRY}/${repository}:latest")
done

# Preflight every source and tag every destination before the first push.
for i in "${!SOURCES[@]}"; do
  echo "publish-acr-images: tagging ${SOURCES[$i]} -> ${TARGETS[$i]}" >&2
  docker tag "${SOURCES[$i]}" "${TARGETS[$i]}"
done
for target in "${TARGETS[@]}"; do
  echo "publish-acr-images: pushing ${target}" >&2
  docker push "$target"
done
