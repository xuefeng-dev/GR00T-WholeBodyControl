#!/usr/bin/env bash
# Run clangd inside g1-deploy-dev so it sees the same toolchain/headers as the build.
set -euo pipefail

CONTAINER="${G1_DEPLOY_CONTAINER:-g1-deploy-dev}"

if ! docker inspect "$CONTAINER" >/dev/null 2>&1; then
  echo "error: container '$CONTAINER' not found; start it first:" >&2
  echo "  gear_sonic_deploy/docker/run-ros2-dev.sh" >&2
  echo "  or: docker start $CONTAINER" >&2
  exit 1
fi

CLANGD_BIN="$(
  docker exec "$CONTAINER" bash -lc '
    command -v clangd 2>/dev/null \
      || command -v clangd-14 2>/dev/null \
      || command -v clangd-15 2>/dev/null \
      || true
  '
)"
if [[ -z "${CLANGD_BIN}" ]]; then
  echo "error: clangd not installed in '$CONTAINER'" >&2
  echo "  docker exec $CONTAINER bash -lc \\" >&2
  echo "    'apt-get update && apt-get install -y clangd-14'" >&2
  exit 1
fi

# -i: forward host stdin to clangd (required for LSP over stdio).
exec docker exec -i "$CONTAINER" "${CLANGD_BIN}" "$@"
