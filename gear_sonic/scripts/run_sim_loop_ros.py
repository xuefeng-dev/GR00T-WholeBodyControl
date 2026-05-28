"""Run MuJoCo sim loop and publish robot pose to ROS2."""

from typing import Any, Dict

from geometry_msgs.msg import PoseStamped
import rclpy
from rclpy.node import Node
import tyro

from gear_sonic.utils.mujoco_sim.simulator_factory import SimulatorFactory, init_channel
from gear_sonic.utils.mujoco_sim.configs import SimLoopConfig
from gear_sonic.data.robot_model.instantiation.g1 import (
    instantiate_g1_robot_model,
)
from gear_sonic.data.robot_model.robot_model import RobotModel

ArgsConfig = SimLoopConfig


class SimWrapper:
    def __init__(self, robot_model: RobotModel, env_name: str, config: Dict[str, Any], **kwargs):
        self.robot_model = robot_model
        self.config = config

        init_channel(config=self.config)

        # Create simulator using factory
        self.sim = SimulatorFactory.create_simulator(
            config=self.config,
            env_name=env_name,
            **kwargs,
        )


class PosePublisherNode(Node):
    def __init__(
        self,
        sim_wrapper: SimWrapper,
        topic_name: str,
        frame_id: str,
        publish_hz: float,
    ):
        super().__init__("mujoco_pose_publisher")
        self.sim_wrapper = sim_wrapper
        self.frame_id = frame_id
        self.publisher = self.create_publisher(PoseStamped, topic_name, 10)
        self.create_timer(1.0 / max(publish_hz, 1.0), self.publish_pose)

    def _read_base_pose(self):
        sim_env = self.sim_wrapper.sim.sim_env
        if sim_env.use_floating_root_link:
            qpos = sim_env.mj_data.qpos
            pos = qpos[:3].copy()
            quat_wxyz = qpos[3:7].copy()
        else:
            root_body = sim_env.mj_data.body("pelvis")
            pos = root_body.xpos.copy()
            quat_wxyz = root_body.xquat.copy()
        return pos, quat_wxyz

    def publish_pose(self):
        # Skip publishing while simulator is not fully running.
        if self.sim_wrapper.sim is None:
            return

        try:
            pos, quat_wxyz = self._read_base_pose()
        except Exception:
            return

        msg = PoseStamped()
        msg.header.stamp = self.get_clock().now().to_msg()
        msg.header.frame_id = self.frame_id
        msg.pose.position.x = float(pos[0])
        msg.pose.position.y = float(pos[1])
        msg.pose.position.z = float(pos[2])
        # MuJoCo quaternion is [w, x, y, z], ROS expects [x, y, z, w].
        msg.pose.orientation.x = float(quat_wxyz[1])
        msg.pose.orientation.y = float(quat_wxyz[2])
        msg.pose.orientation.z = float(quat_wxyz[3])
        msg.pose.orientation.w = float(quat_wxyz[0])
        self.publisher.publish(msg)


def main(config: ArgsConfig):
    wbc_config = config.load_wbc_yaml()
    # NOTE: we will override the interface to local if it is not specified
    wbc_config["ENV_NAME"] = config.env_name

    if config.enable_image_publish:
        assert (
            config.enable_offscreen
        ), "enable_offscreen must be True when enable_image_publish is True"

    robot_model = instantiate_g1_robot_model()

    sim_wrapper = SimWrapper(
        robot_model=robot_model,
        env_name=config.env_name,
        config=wbc_config,
        onscreen=wbc_config.get("ENABLE_ONSCREEN", True),
        offscreen=wbc_config.get("ENABLE_OFFSCREEN", False),
        enable_image_publish=config.enable_image_publish,
    )

    # ROS2 pose publish settings (can be overridden by config fields if added later).
    pose_topic = getattr(config, "ros2_pose_topic", "/mujoco/base_pose")
    pose_frame = getattr(config, "ros2_pose_frame_id", "world")
    pose_hz = float(getattr(config, "ros2_pose_publish_hz", 50.0))

    rclpy.init()
    pose_node = PosePublisherNode(
        sim_wrapper=sim_wrapper,
        topic_name=pose_topic,
        frame_id=pose_frame,
        publish_hz=pose_hz,
    )

    # Start simulator in a thread, then spin ROS2 in main thread.
    SimulatorFactory.start_simulator(
        sim_wrapper.sim,
        as_thread=True,
        enable_image_publish=config.enable_image_publish,
        mp_start_method=config.mp_start_method,
        camera_port=config.camera_port,
    )

    try:
        while rclpy.ok():
            if sim_wrapper.sim.sim_thread is not None and not sim_wrapper.sim.sim_thread.is_alive():
                break
            rclpy.spin_once(pose_node, timeout_sec=0.1)
    except KeyboardInterrupt:
        pass
    finally:
        pose_node.destroy_node()
        if rclpy.ok():
            rclpy.shutdown()
        sim_wrapper.sim.close()
        if sim_wrapper.sim.sim_thread is not None:
            sim_wrapper.sim.sim_thread.join(timeout=1.0)


if __name__ == "__main__":
    config = tyro.cli(ArgsConfig)
    main(config)