#!/bin/bash
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${DEPLOY_ROOT}"

LOG_DIR="${DEPLOY_ROOT}/logs"
mkdir -p "${LOG_DIR}"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
LOG_FILE="${LOG_DIR}/real_policy_ros2_${TIMESTAMP}.log"

echo "Logging to: ${LOG_FILE}"
{
  echo "=== start_real_policy_ros2.sh ==="
  echo "Started at: $(date -Iseconds)"
  echo "Host: $(hostname)"
  echo "Deploy root: ${DEPLOY_ROOT}"
  echo "================================="

  source "${SCRIPT_DIR}/setup_env.sh"
  bash deploy.sh --input-type ros2 --ros2-policy-start gamepad real
} 2>&1 | tee -a "${LOG_FILE}"
