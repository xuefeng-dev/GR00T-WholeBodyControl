#!/usr/bin/env bash
# Run clangd inside g1-deploy-dev so it sees the same toolchain/headers as the build.
# Maps host gear_sonic_deploy paths to the container mount at /workspace/g1_deploy.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOST_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
CONTAINER_ROOT="/workspace/g1_deploy"

CONTAINER="${G1_DEPLOY_CONTAINER:-g1-deploy-dev}"

if ! docker inspect "$CONTAINER" >/dev/null 2>&1; then
  echo "error: container '$CONTAINER' not found; start it first:" >&2
  echo "  gear_sonic_deploy/docker/run-ros2-dev.sh" >&2
  echo "  or: docker start $CONTAINER" >&2
  exit 1
fi

if [[ "$(docker inspect -f '{{.State.Running}}' "$CONTAINER")" != "true" ]]; then
  echo "error: container '$CONTAINER' is not running; start it first:" >&2
  echo "  docker start $CONTAINER" >&2
  echo "  or: gear_sonic_deploy/docker/run-ros2-dev.sh" >&2
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
exec docker exec -i "$CONTAINER" "${CLANGD_BIN}" \
  --path-mappings="${HOST_ROOT}=${CONTAINER_ROOT}" \
  --compile-commands-dir="${CONTAINER_ROOT}/build" \
  "$@"
