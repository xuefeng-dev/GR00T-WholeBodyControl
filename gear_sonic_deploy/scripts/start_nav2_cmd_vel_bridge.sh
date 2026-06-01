#!/usr/bin/env bash
# Nav2 /cmd_vel → ControlPolicy/upper_body_pose 桥接（需已 source ROS2）
set -euo pipefail
DEPLOY_DIR="$(cd "$(dirname "$0")/.." && pwd)"
if [ -f /opt/ros/humble/setup.bash ]; then
  set +u
  # shellcheck source=/dev/null
  source /opt/ros/humble/setup.bash
  set -u
fi

export PYTHONPATH="${DEPLOY_DIR}/python:${PYTHONPATH}"
cd "${DEPLOY_DIR}"
exec python3 -m nav2.cmd_vel_bridge "$@"
