#!/usr/bin/env bash
# Nav2 桥接 Python 依赖（容器内 apt 安装）
set -euo pipefail
if ! command -v apt-get >/dev/null 2>&1; then
  echo "ERROR: apt-get not found"
  exit 1
fi
export DEBIAN_FRONTEND=noninteractive
apt-get update -q
apt-get install -y -q python3-msgpack python3-msgpack-numpy
echo "Nav2 bridge Python deps installed (msgpack, msgpack-numpy)."
