#!/bin/bash
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${DEPLOY_ROOT}"

source "${SCRIPT_DIR}/setup_env.sh"
bash deploy.sh --input-type ros2 --ros2-policy-start keyboard sim
