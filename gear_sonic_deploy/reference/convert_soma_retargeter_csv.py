#!/usr/bin/env python3
"""将 SOMA Retargeter 导出的 G1 CSV 转为 C++ 部署可读格式。"""

from __future__ import annotations

import argparse
import csv
import os
import re
import sys
from pathlib import Path

import numpy as np
from scipy.interpolate import interp1d
from scipy.spatial.transform import Rotation as R, Slerp

# IsaacLab 索引 -> MuJoCo 关节索引（与 visualize_motion.py 一致）
ISAACLAB_TO_MUJOCO = np.array(
    [
        0, 3, 6, 9, 13, 17, 1, 4, 7, 10, 14, 18, 2, 5, 8, 11, 15, 19, 21, 23,
        25, 27, 12, 16, 20, 22, 24, 26, 28,
    ],
    dtype=int,
)


def _sanitize_motion_name(name: str) -> str:
    # 去掉不安全字符，保留可读名称
    return re.sub(r"[^\w\-.]+", "_", name).strip("_")


def load_soma_retargeter_csv(csv_path: str) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    """解析 SOMA Retargeter 的 unitree_g1 CSV。"""
    with open(csv_path, newline="", encoding="utf-8") as f:
        rows = list(csv.reader(f))

    if len(rows) < 2:
        raise ValueError(f"CSV 为空: {csv_path}")

    data = np.loadtxt(csv_path, delimiter=",", skiprows=1, dtype=np.float64)
    # 列: frame, tx(cm), ty, tz, euler_xyz(deg), 29 joints(deg)
    trans = data[:, 1:4] * 0.01
    euler = np.deg2rad(data[:, 4:7])
    quat_xyzw = R.from_euler("xyz", euler).as_quat()
    joints_mj = np.deg2rad(data[:, 7:36])
    return trans, quat_xyzw, joints_mj


def mujoco_to_isaaclab(joints_mj: np.ndarray) -> np.ndarray:
    """MuJoCo 关节角 -> IsaacLab 顺序。"""
    joints_il = np.zeros_like(joints_mj)
    for mj_idx, il_idx in enumerate(ISAACLAB_TO_MUJOCO):
        joints_il[:, il_idx] = joints_mj[:, mj_idx]
    return joints_il


def resample_motion(
    trans: np.ndarray,
    quat_xyzw: np.ndarray,
    joints_mj: np.ndarray,
    src_fps: float,
    dst_fps: float,
) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    """线性插值平移/关节，球面插值根姿态。"""
    num_frames = trans.shape[0]
    if num_frames < 2:
        return trans, quat_xyzw, joints_mj

    src_t = np.arange(num_frames, dtype=np.float64) / src_fps
    duration = src_t[-1]
    dst_t = np.arange(0.0, duration + 1e-9, 1.0 / dst_fps)

    trans_new = interp1d(src_t, trans, axis=0, kind="linear")(dst_t)
    joints_new = interp1d(src_t, joints_mj, axis=0, kind="linear")(dst_t)
    slerp = Slerp(src_t, R.from_quat(quat_xyzw))
    quat_new = slerp(dst_t).as_quat()
    return trans_new, quat_new, joints_new


def save_array_as_csv(array: np.ndarray, filename: str, headers: list[str]) -> None:
    with open(filename, "w", encoding="utf-8") as f:
        f.write(",".join(headers) + "\n")
        for row in array:
            f.write(",".join(f"{val:.6f}" for val in row) + "\n")


def convert_single_csv(
    csv_path: str,
    output_dir: str,
    motion_name: str,
    src_fps: float,
    dst_fps: float,
) -> None:
    trans, quat_xyzw, joints_mj = load_soma_retargeter_csv(csv_path)
    trans, quat_xyzw, joints_mj = resample_motion(
        trans, quat_xyzw, joints_mj, src_fps=src_fps, dst_fps=dst_fps
    )

    joint_pos_il = mujoco_to_isaaclab(joints_mj)
    dt = 1.0 / dst_fps
    joint_vel_il = np.gradient(joint_pos_il, dt, axis=0)

    # body_quat: wxyz；MuJoCo qpos 与 visualize_motion 一致
    body_quat_wxyz = quat_xyzw[:, [3, 0, 1, 2]]
    body_pos = trans

    os.makedirs(output_dir, exist_ok=True)
    timesteps = joint_pos_il.shape[0]

    save_array_as_csv(
        joint_pos_il,
        os.path.join(output_dir, "joint_pos.csv"),
        [f"joint_{i}" for i in range(29)],
    )
    save_array_as_csv(
        joint_vel_il,
        os.path.join(output_dir, "joint_vel.csv"),
        [f"joint_vel_{i}" for i in range(29)],
    )
    save_array_as_csv(
        body_pos,
        os.path.join(output_dir, "body_pos.csv"),
        ["body_0_x", "body_0_y", "body_0_z"],
    )
    save_array_as_csv(
        body_quat_wxyz,
        os.path.join(output_dir, "body_quat.csv"),
        ["body_0_w", "body_0_x", "body_0_y", "body_0_z"],
    )

    with open(os.path.join(output_dir, "metadata.txt"), "w", encoding="utf-8") as f:
        f.write(f"Metadata for: {motion_name}\n")
        f.write("=" * 30 + "\n\n")
        f.write("Body part indexes:\n")
        f.write("[0]\n\n")
        f.write(f"Total timesteps: {timesteps}\n")
        f.write(f"Source fps: {src_fps}\n")
        f.write(f"Target fps: {dst_fps}\n")

    print(
        f"  ✓ {motion_name}: {timesteps} frames @ {dst_fps} Hz -> {output_dir}"
    )


def convert_folder(
    input_dir: str,
    output_dir: str,
    src_fps: float,
    dst_fps: float,
) -> int:
    csv_files = sorted(Path(input_dir).glob("*.csv"))
    if not csv_files:
        print(f"未找到 CSV: {input_dir}")
        return 0

    os.makedirs(output_dir, exist_ok=True)
    count = 0
    for csv_path in csv_files:
        motion_name = _sanitize_motion_name(csv_path.stem)
        motion_out = os.path.join(output_dir, motion_name)
        print(f"Processing: {csv_path.name}")
        convert_single_csv(
            str(csv_path),
            motion_out,
            motion_name,
            src_fps=src_fps,
            dst_fps=dst_fps,
        )
        count += 1
    return count


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Convert SOMA Retargeter G1 CSV to deploy motion folders."
    )
    parser.add_argument("input_dir", help="Directory of SOMA Retargeter CSV files")
    parser.add_argument(
        "output_dir",
        help="Output base directory (one subfolder per motion)",
    )
    parser.add_argument(
        "--src-fps",
        type=float,
        default=30.0,
        help="Source motion fps (default: 30)",
    )
    parser.add_argument(
        "--dst-fps",
        type=float,
        default=50.0,
        help="Deploy motion fps (default: 50)",
    )
    args = parser.parse_args()

    if not os.path.isdir(args.input_dir):
        print(f"输入目录不存在: {args.input_dir}", file=sys.stderr)
        return 1

    count = convert_folder(
        args.input_dir,
        args.output_dir,
        src_fps=args.src_fps,
        dst_fps=args.dst_fps,
    )
    print(f"\n完成: {count} 条动作 -> {args.output_dir}")
    return 0 if count > 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
