#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="${ROOT}/build/compile_commands.json"
DST="${ROOT}/compile_commands.json"

if [[ ! -f "${SRC}" ]]; then
  echo "error: ${SRC} not found; run cmake with -DCMAKE_EXPORT_COMPILE_COMMANDS=ON" >&2
  exit 1
fi

ln -sf build/compile_commands.json "${DST}"
echo "linked ${DST} -> build/compile_commands.json"
