#!/usr/bin/env bash
# 修复项目移动路径后 virtualenv 中残留的旧仓库绝对路径。
#
# Usage:
#   bash scripts/repair_venv_paths.sh
#   bash scripts/repair_venv_paths.sh .venv_sim

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$REPO_ROOT"

if ! command -v python3 &>/dev/null; then
    echo "[ERROR] python3 not found on PATH."
    exit 1
fi

# 未指定参数时，默认处理仓库根目录下的所有 .venv*。
if [ "$#" -gt 0 ]; then
    VENV_PATHS=("$@")
else
    shopt -s nullglob
    VENV_PATHS=(.venv*)
    shopt -u nullglob
fi

if [ "${#VENV_PATHS[@]}" -eq 0 ]; then
    echo "[WARN] No .venv* directories found."
    exit 0
fi

for VENV_PATH in "${VENV_PATHS[@]}"; do
    if [ ! -d "$VENV_PATH" ]; then
        echo "[WARN] Skipping missing directory: $VENV_PATH"
        continue
    fi

    VENV_ABS="$(cd "$VENV_PATH" && pwd)"
    VENV_NAME="$(basename "$VENV_ABS")"

    echo "[INFO] Repairing $VENV_NAME"
    echo "[INFO] Current venv path: $VENV_ABS"

    python3 - "$VENV_ABS" "$VENV_NAME" "$REPO_ROOT" <<'PY'
from __future__ import annotations

import re
import shutil
import sys
from pathlib import Path

venv = Path(sys.argv[1]).resolve()
venv_name = sys.argv[2]
repo_root = Path(sys.argv[3]).resolve()

old_roots: set[str] = set()
fixed_shebangs = 0

# 从 activate 文件中提取旧 VIRTUAL_ENV，反推出旧仓库路径。
for activate in [
    venv / "bin" / "activate",
    venv / "bin" / "activate.csh",
    venv / "bin" / "activate.fish",
    venv / "bin" / "activate.nu",
]:
    if not activate.exists():
        continue
    text = activate.read_text(errors="ignore")
    for match in re.finditer(rf"(/[^\s'\";]+/{re.escape(venv_name)})", text):
        old_venv = Path(match.group(1))
        if old_venv.name == venv_name:
            old_roots.add(str(old_venv.parent))

# 从 bin 下脚本 shebang 中提取旧路径。
bin_dir = venv / "bin"
if bin_dir.exists():
    for script in bin_dir.iterdir():
        if not script.is_file():
            continue
        try:
            with script.open("rb") as fh:
                first_line = fh.readline().decode(errors="ignore")
        except OSError:
            continue
        marker = f"/{venv_name}/bin/python"
        if first_line.startswith("/") and marker in first_line:
            # 修复异常中断或错误替换导致的脚本头缺失。
            text = script.read_text(errors="ignore")
            script.write_text("#!" + text)
            first_line = "#!" + first_line
            fixed_shebangs += 1
        if first_line.startswith("#!") and marker in first_line:
            shebang_path = first_line[2:].strip()
            old_roots.add(shebang_path.split(marker, 1)[0])

# 从 editable 安装元数据中提取旧仓库路径。
site_packages = venv / "lib"
if site_packages.exists():
    for meta in site_packages.rglob("*"):
        if not meta.is_file() or meta.suffix not in {".pth", ".json", ".py"}:
            continue
        try:
            text = meta.read_text(errors="ignore")
        except OSError:
            continue
        for match in re.finditer(r"file://(/[^\"]+)", text):
            path = Path(match.group(1))
            for parent in [path, *path.parents]:
                if (parent / venv_name).exists() or parent.name == repo_root.name:
                    old_roots.add(str(parent))
                    break
        for line in text.splitlines():
            if line.startswith("/") and repo_root.name in line:
                path = Path(line.strip())
                old_roots.add(str(path if path.name == repo_root.name else path.parent))

old_roots.discard(str(repo_root))

if not old_roots:
    if fixed_shebangs:
        print(f"[OK] Fixed {fixed_shebangs} script shebangs.")
    print("[OK] No stale repo paths found.")
    raise SystemExit(0)

print("[INFO] Stale repo paths:")
for old in sorted(old_roots):
    print(f"       {old}")

replacements = {old: str(repo_root) for old in old_roots}
changed = 0

for path in venv.rglob("*"):
    if not path.is_file() or path.suffix == ".pyc":
        continue
    try:
        data = path.read_bytes()
    except OSError:
        continue
    if b"\0" in data:
        continue
    text = data.decode(errors="ignore")
    new_text = text
    for old, new in replacements.items():
        new_text = new_text.replace(old, new)
    if new_text != text:
        path.write_text(new_text)
        changed += 1

# 编译缓存中也可能保留旧文件名，直接清理即可。
removed_caches = 0
for cache_dir in venv.rglob("__pycache__"):
    if cache_dir.is_dir():
        shutil.rmtree(cache_dir)
        removed_caches += 1

print(f"[OK] Updated {changed} files.")
if fixed_shebangs:
    print(f"[OK] Fixed {fixed_shebangs} script shebangs.")
print(f"[OK] Removed {removed_caches} __pycache__ directories.")
PY
done

echo "[OK] Repair complete."
