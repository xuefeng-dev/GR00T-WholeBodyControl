#!/usr/bin/env bash
# Configure CMake in the dev container and refresh compile_commands.json on the host mount.
set -euo pipefail

CONTAINER="${G1_DEPLOY_CONTAINER:-g1-deploy-dev}"
BUILD_TYPE="${BUILD_TYPE:-Release}"

if ! docker inspect "$CONTAINER" >/dev/null 2>&1; then
  echo "error: container '$CONTAINER' not found" >&2
  exit 1
fi

docker exec "$CONTAINER" bash -lc "$(cat <<EOF
set -eo pipefail
cd /workspace/g1_deploy
# HAS_ROS2=1 must be exported before cmake (see src/g1/g1_deploy_onnx_ref/CMakeLists.txt)
set +u
source scripts/setup_env.sh
set -u
export HAS_ROS2="\${HAS_ROS2:-1}"
mkdir -p build
cd build
cmake -S .. -B . -DCMAKE_BUILD_TYPE=${BUILD_TYPE} -DCMAKE_EXPORT_COMPILE_COMMANDS=ON
echo "cmake HAS_ROS2 env=\$HAS_ROS2"
EOF
)"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
bash "${ROOT}/scripts/sync_compile_commands.sh"
echo "compile_commands ready at ${ROOT}/build/compile_commands.json"
