#!/usr/bin/env bash
set -euo pipefail

SCRIPTS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_DIR="$(mktemp -d)"
trap 'rm -f "$TEST_DIR/docker" "$TEST_DIR/log"; rmdir "$TEST_DIR"' EXIT
export DOCKER_LOG="${TEST_DIR}/log"
export PATH="${TEST_DIR}:${PATH}"
export NOVA_VE_ACR_REGISTRY=example.azurecr.io
unset NOVA_VE_SKIP_DEMO_IMAGES NOVA_VE_SKIP_PLATFORM_IMAGES \
  NOVA_VE_PLATFORM_MODE NOVA_VE_PLATFORM_PULL GHCR_PUSH

cat > "${TEST_DIR}/docker" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$DOCKER_LOG"
if [[ -n "${FAIL_MATCH:-}" && "$*" == *"$FAIL_MATCH"* ]]; then
  exit 1
fi
if [[ "$1" == "images" ]]; then
  if [[ "${@: -1}" != nova-ve-lab/* ]]; then
    printf 'mock-image-id\n'
  fi
  exit 0
fi
MOCK
chmod +x "${TEST_DIR}/docker"

fail() { echo "test-acr-images: $*" >&2; exit 1; }
reset_log() { : > "$DOCKER_LOG"; }
expect_no_push() {
  if grep -q '^push ' "$DOCKER_LOG"; then
    fail "unexpected push"
  fi
}

reset_log
NOVA_VE_ACR_REGISTRY= bash "${SCRIPTS}/publish-acr-images.sh"
[[ ! -s "$DOCKER_LOG" ]] || fail "unset registry must not invoke Docker"
if NOVA_VE_ACR_REGISTRY=https://example.azurecr.io \
  bash "${SCRIPTS}/publish-acr-images.sh" --check; then
  fail "invalid registry accepted"
fi
[[ ! -s "$DOCKER_LOG" ]] || fail "invalid registry must not invoke Docker"

reset_log
bash "${SCRIPTS}/publish-acr-images.sh" \
  nova-ve/browser:1.2 postgres:16-alpine\|nova-ve/runtime/postgres-alpine
grep -qx 'tag nova-ve/browser:1.2 example.azurecr.io/nova-ve/browser:latest' "$DOCKER_LOG" \
  || fail "version tag not normalized"
grep -qx 'push example.azurecr.io/nova-ve/runtime/postgres-alpine:latest' "$DOCKER_LOG" \
  || fail "runtime variant mapping incorrect"
awk '/^push / {pushed=1} /^tag / && pushed {exit 1}' "$DOCKER_LOG" \
  || fail "tagging occurred after pushing"

reset_log
if FAIL_MATCH='image inspect nova-ve/desktop' \
  bash "${SCRIPTS}/publish-acr-images.sh"; then
  fail "missing image did not fail"
fi
expect_no_push
if grep -q '^tag ' "$DOCKER_LOG"; then
  fail "tagging started before all images were checked"
fi

reset_log
if FAIL_MATCH='tag nova-ve/browser' \
  bash "${SCRIPTS}/publish-acr-images.sh" nova-ve/browser:latest; then
  fail "tag failure swallowed"
fi
expect_no_push

reset_log
if FAIL_MATCH='push example.azurecr.io/nova-ve/browser' \
  bash "${SCRIPTS}/publish-acr-images.sh" nova-ve/browser:latest; then
  fail "push failure swallowed"
fi

reset_log
bash "${SCRIPTS}/build-all-images.sh"
[[ "$(grep -c '^build ' "$DOCKER_LOG")" == "8" ]] || fail "not all Dockerfiles built"
[[ "$(grep -c '^push ' "$DOCKER_LOG")" == "14" ]] || fail "not all repository images pushed"
[[ "$(grep '^push ' "$DOCKER_LOG" | sort -u | wc -l)" == "14" ]] \
  || fail "destination tags collide"
awk '/^push / {pushed=1} /^(build|pull|tag) / && pushed {exit 1}' "$DOCKER_LOG" \
  || fail "publication started before images were ready"
if grep '^push ' "$DOCKER_LOG" | grep -vE '^push example\.azurecr\.io/.+:latest$'; then
  fail "push outside configured ACR or with a version tag"
fi

reset_log
if FAIL_MATCH='build -t nova-ve/desktop' bash "${SCRIPTS}/build-all-images.sh"; then
  fail "build failure swallowed"
fi
expect_no_push

reset_log
NOVA_VE_ACR_REGISTRY= bash "${SCRIPTS}/build-all-images.sh"
[[ "$(grep -c '^build ' "$DOCKER_LOG")" == "8" ]] || fail "local-only builds incomplete"
expect_no_push

reset_log
bash "${SCRIPTS}/build-demo-images.sh"
[[ "$(grep -c '^push ' "$DOCKER_LOG")" == "3" ]] || fail "demo publication missing"
awk '/^push / {pushed=1} /^(build|pull|tag) / && pushed {exit 1}' "$DOCKER_LOG" \
  || fail "demo publication started too early"

reset_log
NOVA_VE_PLATFORM_MODE=pull bash "${SCRIPTS}/build-platform-images.sh"
grep -qx 'pull example.azurecr.io/nova-ve/browser:latest' "$DOCKER_LOG" \
  || fail "platform pull did not use ACR"
[[ "$(grep -c '^push ' "$DOCKER_LOG")" == "3" ]] || fail "platform publication missing"

reset_log
if NOVA_VE_PLATFORM_MODE=pull FAIL_MATCH='pull example.azurecr.io/nova-ve/browser' \
  bash "${SCRIPTS}/build-platform-images.sh"; then
  fail "pull failure swallowed"
fi
expect_no_push

echo "test-acr-images: passed."
