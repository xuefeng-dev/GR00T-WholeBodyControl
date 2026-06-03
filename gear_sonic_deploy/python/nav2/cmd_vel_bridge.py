"""
Nav2 /cmd_vel → ControlPolicy/upper_body_pose 桥接节点。

订阅 geometry_msgs/msg/Twist（/cmd_vel），转换为 g1_deploy 所需的 msgpack
ControlGoal（navigate_cmd、locomotion_mode 等），并以 ≥50 Hz 发布。
"""

from __future__ import annotations

import argparse
import math
import time

import msgpack
import msgpack_numpy as mnp
import rclpy
from geometry_msgs.msg import Twist
from rclpy.node import Node
from std_msgs.msg import ByteMultiArray

from constants import (
    CONTROL_GOAL_TOPIC,
    DEFAULT_BASE_HEIGHT,
    DEFAULT_WRIST_POSE,
)

NODE_NAME = "nav2_cmd_vel_bridge"
DEFAULT_CMD_VEL_TOPIC = "/cmd_vel"
DEFAULT_PUBLISH_HZ = 50.0
WALK_SPEED_THRESHOLD_MPS = 1.5
LOCOMOTION_MODE_WALK = 1
LOCOMOTION_MODE_RUN = 2
CMD_VEL_TIMEOUT_SEC = 0.5


def _pack_control_goal(payload: dict) -> ByteMultiArray:
    packed = msgpack.packb(payload, default=mnp.encode)
    msg = ByteMultiArray()
    msg.data = [bytes([b]) for b in packed]
    return msg


def _linear_speed_mps(vx: float, vy: float) -> float:
    return math.hypot(vx, vy)


def _locomotion_mode_from_speed(speed_mps: float, threshold: float) -> int:
    if speed_mps <= 0.8:
        return 0
    elif speed_mps <= 1.5:
        return 1
    else:
        return 2


class Nav2CmdVelBridge(Node):
    def __init__(
        self,
        cmd_vel_topic: str,
        control_goal_topic: str,
        publish_hz: float,
        walk_speed_threshold: float,
        base_height: float,
    ) -> None:
        super().__init__(NODE_NAME)
        self._walk_speed_threshold = walk_speed_threshold
        self._base_height = base_height

        self._vx = 0.0
        self._wz = 0.0
        self._last_cmd_vel_time: float | None = None

        self._publisher = self.create_publisher(
            ByteMultiArray, control_goal_topic, 10
        )
        self.create_subscription(Twist, cmd_vel_topic, self._on_cmd_vel, 10)

        period_sec = 1.0 / publish_hz
        self.create_timer(period_sec, self._on_timer)
        self.get_logger().info(
            f"Subscribed to {cmd_vel_topic}, publishing {control_goal_topic} "
            f"@ {publish_hz:.0f} Hz; linear speed <= {walk_speed_threshold} m/s "
            f"-> locomotion_mode={LOCOMOTION_MODE_WALK}, "
            f"> {walk_speed_threshold} m/s -> locomotion_mode={LOCOMOTION_MODE_RUN}"
        )

    def _on_cmd_vel(self, msg: Twist) -> None:
        self._vx = float(msg.linear.x)
        self._vy = float(msg.linear.y)
        self._wz = float(msg.angular.z)
        self._last_cmd_vel_time = time.monotonic()
        print(f"Received cmd_vel: {msg}")

    def _current_velocities(self) -> tuple[float, float, float]:
        if self._last_cmd_vel_time is None:
            return 0.0, 0.0, 0.0

        if time.monotonic() - self._last_cmd_vel_time > CMD_VEL_TIMEOUT_SEC:
            return 0.0, 0.0, 0.0

        return self._vx, self._vy, self._wz

    def _on_timer(self) -> None:
        vx, vy, wz = self._current_velocities()
        speed = _linear_speed_mps(vx, vy)
        locomotion_mode = _locomotion_mode_from_speed(
            speed, self._walk_speed_threshold
        )

        payload = {
            "navigate_cmd": [vx, vy, wz],
            "wrist_pose": list(DEFAULT_WRIST_POSE),
            "base_height_command": self._base_height,
            "locomotion_mode": locomotion_mode,
            "ros_timestamp": self.get_clock().now().nanoseconds * 1e-9,
        }
        # print(f"Publishing control goal: {payload}")
        self._publisher.publish(_pack_control_goal(payload))


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Bridge Nav2 /cmd_vel to ControlPolicy/upper_body_pose"
    )
    parser.add_argument(
        "--cmd-vel-topic",
        default=DEFAULT_CMD_VEL_TOPIC,
        help=f"Nav2 velocity topic (default: {DEFAULT_CMD_VEL_TOPIC})",
    )
    parser.add_argument(
        "--control-goal-topic",
        default=CONTROL_GOAL_TOPIC,
        help=f"g1_deploy control goal topic (default: {CONTROL_GOAL_TOPIC})",
    )
    parser.add_argument(
        "--publish-hz",
        type=float,
        default=DEFAULT_PUBLISH_HZ,
        help=f"Publish rate in Hz (default: {DEFAULT_PUBLISH_HZ})",
    )
    parser.add_argument(
        "--walk-speed-threshold",
        type=float,
        default=WALK_SPEED_THRESHOLD_MPS,
        help=(
            f"Linear speed <= threshold -> locomotion_mode={LOCOMOTION_MODE_WALK}, "
            f"> threshold -> locomotion_mode={LOCOMOTION_MODE_RUN} "
            f"(default: {WALK_SPEED_THRESHOLD_MPS} m/s)"
        ),
    )
    parser.add_argument(
        "--base-height",
        type=float,
        default=DEFAULT_BASE_HEIGHT,
        help=f"base_height_command value (default: {DEFAULT_BASE_HEIGHT})",
    )
    return parser.parse_args()


def main() -> None:
    args = _parse_args()
    rclpy.init()
    node = Nav2CmdVelBridge(
        cmd_vel_topic=args.cmd_vel_topic,
        control_goal_topic=args.control_goal_topic,
        publish_hz=args.publish_hz,
        walk_speed_threshold=args.walk_speed_threshold,
        base_height=args.base_height,
    )
    try:
        rclpy.spin(node)
    except KeyboardInterrupt:
        pass
    finally:
        node.destroy_node()
        rclpy.shutdown()


if __name__ == "__main__":
    main()
