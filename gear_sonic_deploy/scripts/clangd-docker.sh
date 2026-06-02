#!/usr/bin/env bash
# Run clangd inside ${USER}-g1-deploy-dev so it sees the same toolchain/headers as the build.
# Maps host gear_sonic_deploy paths to the container mount at /workspace/g1_deploy.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOST_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
CONTAINER_ROOT="/workspace/g1_deploy"

CONTAINER="${G1_DEPLOY_CONTAINER:-${USER}-g1-deploy-dev}"

if ! docker inspect "$CONTAINER" >/dev/null 2>&1; then
  echo "error: container '$CONTAINER' not found; start it first:" >&2
  echo "  gear_sonic_deploy/docker/run-ros2-dev.sh" >&2
  exit 1
fi

if [[ "$(docker inspect -f '{{.State.Running}}' "$CONTAINER")" != "true" ]]; then
  echo "Starting container '$CONTAINER'..." >&2
  if ! docker start "$CONTAINER" >/dev/null 2>&1; then
    echo "error: container '$CONTAINER' is not running; start it first:" >&2
    echo "  scripts/exec_docker.sh" >&2
    echo "  or: gear_sonic_deploy/docker/run-ros2-dev.sh" >&2
    exit 1
  fi
fi

find_clangd() {
  docker exec "$CONTAINER" bash -lc '
    command -v clangd 2>/dev/null \
      || command -v clangd-14 2>/dev/null \
      || command -v clangd-15 2>/dev/null \
      || true
  '
}

CLANGD_BIN="$(find_clangd)"
if [[ -z "${CLANGD_BIN}" ]]; then
  echo "Installing clangd-14 in '$CONTAINER' (one-time)..." >&2
  docker exec "$CONTAINER" bash -lc \
    'DEBIAN_FRONTEND=noninteractive apt-get update -qq \
      && apt-get install -y -qq clangd-14'
  CLANGD_BIN="$(find_clangd)"
fi
if [[ -z "${CLANGD_BIN}" ]]; then
  echo "error: clangd not available in '$CONTAINER'" >&2
  exit 1
fi

# -i: forward host stdin to clangd (required for LSP over stdio).
exec docker exec -i "$CONTAINER" "${CLANGD_BIN}" \
  --path-mappings="${HOST_ROOT}=${CONTAINER_ROOT}" \
  --compile-commands-dir="${CONTAINER_ROOT}/build" \
  "$@"
