#!/usr/bin/env bash
# Kimodo SOMA NPZ -> G1 部署格式（Motion Reference CSV）
# 依赖: kimodo (kimodo_convert)、soma-retargeter (uv)、.venv_sim
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
INPUT_DIR="${1:-$ROOT/sample_data/Kimodo-SOMA-RP-v1}"
OUTPUT_DIR="${2:-$INPUT_DIR/g1_deploy}"

BVH_DIR="$INPUT_DIR/bvh_bones_seed"
CSV_RAW_DIR="$INPUT_DIR/g1_csv_bones_seed"
RETARGET_CONFIG="/tmp/kimodo_soma_to_g1_retarget.json"

PYTHON="$ROOT/.venv_sim/bin/python"
KIMODO_CONVERT="$ROOT/.venv_sim/bin/kimodo_convert"
SOMA_RETARGETER="${SOMA_RETARGETER:-/tmp/soma-retargeter}"

if [[ ! -x "$PYTHON" ]]; then
  echo "Missing venv: $PYTHON" >&2
  exit 1
fi
if [[ ! -x "$KIMODO_CONVERT" ]]; then
  echo "Missing kimodo_convert. Install: uv pip install -e /path/to/kimodo --python $PYTHON" >&2
  exit 1
fi
if [[ ! -d "$SOMA_RETARGETER" ]]; then
  echo "Missing soma-retargeter at $SOMA_RETARGETER" >&2
  echo "Clone: git clone --depth 1 https://github.com/NVIDIA/soma-retargeter.git $SOMA_RETARGETER" >&2
  exit 1
fi

mkdir -p "$BVH_DIR" "$CSV_RAW_DIR" "$OUTPUT_DIR"

echo "[1/3] Kimodo NPZ -> SOMA BVH (BONES-SEED rest pose, no --bvh_standard_tpose)"
for npz in "$INPUT_DIR"/*.npz; do
  [[ -f "$npz" ]] || continue
  base="$(basename "$npz" .npz)"
  out="$BVH_DIR/${base}.bvh"
  echo "  $base"
  # SOMA Retargeter 期望 BONES-SEED rest pose，勿加 --bvh_standard_tpose
  "$KIMODO_CONVERT" "$npz" "$out"
done

cat > "$RETARGET_CONFIG" <<EOF
{
  "import_folder": "$BVH_DIR",
  "export_folder": "$CSV_RAW_DIR",
  "batch_size": 8,
  "retargeter": "Newton",
  "retarget_source": "soma",
  "retarget_target": "unitree_g1",
  "retarget_source_facing_direction": "Mujoco"
}
EOF

echo "[2/3] SOMA Retargeter: BVH -> G1 CSV"
(cd "$SOMA_RETARGETER" && uv run python ./app/bvh_to_csv_converter.py \
  --config "$RETARGET_CONFIG" --viewer null)

echo "[3/3] G1 CSV -> deploy motion folders (50 Hz)"
"$PYTHON" "$ROOT/gear_sonic_deploy/reference/convert_soma_retargeter_csv.py" \
  "$CSV_RAW_DIR" "$OUTPUT_DIR" --src-fps 30 --dst-fps 50

echo ""
echo "Done. Output: $OUTPUT_DIR"
echo "Visualize:"
echo "  cd $ROOT/gear_sonic_deploy"
echo "  $PYTHON visualize_motion.py --motion_dir $OUTPUT_DIR"
