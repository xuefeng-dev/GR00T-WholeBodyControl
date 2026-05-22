# ROS2 接口 Demo

`demo_ros2_control_publisher.cpp` 演示如何向 **g1_deploy** 发送 ROS2 控制指令。代码尽量写在 `main()` 里，便于阅读与拷贝。

完整自动化测试见：`tests/test_ros2_control_publisher.cpp`。

## 编译

在启用 ROS2 的环境下构建（与主程序相同）：

```bash
export HAS_ROS2=1
# 在 gear_sonic_deploy 工程目录按项目惯例编译
```

产物：`target/release/demo_ros2_control_publisher`

## 运行

终端 1 — 仿真（可选）：

```bash
python gear_sonic/scripts/run_sim_loop.py
```

终端 2 — 策略（ROS2 输入）：

```bash
./scripts/start_sim_policy_ros2.sh
# 等待出现 Init Done
```

终端 3 — 本 demo：

```bash
./target/release/demo_ros2_control_publisher
```

## 话题与消息格式

### 输入（本 demo 发布）

| 话题 | 类型 | 说明 |
|------|------|------|
| `ControlPolicy/upper_body_pose` | `std_msgs/msg/ByteMultiArray` | `data` 为 msgpack 编码的 map |

常用字段（map 键 → 类型）：

| 键 | 类型 | 说明 |
|----|------|------|
| `navigate_cmd` | `double[3]` | `[线速度x, 线速度y, 角速度z]` |
| `wrist_pose` | `double[14]` | 左右手腕位姿，各 7 元 `[x,y,z,qw,qx,qy,qz]` |
| `base_height_command` | `double` | 机身高度指令，常用约 `0.78` |
| `locomotion_mode` | `int` | `0` 慢走，`1` 快走，`2` 跑 |
| `ros_timestamp` | `double` | ROS 时间（秒），建议用节点时钟 |
| `toggle_policy_action` | `bool` | **边沿触发**：发一次 `true` 在 START/STOP 间切换 |

可选字段（上肢/手）：`left_wrist_after_ik`、`right_wrist_after_ik`、`head_after_ik`、`left_hand_joint` 等，见 `include/input_interface/ros2_input_handler.hpp` 文件头注释。

**注意**：`toggle_policy_action` 不要每帧发送，否则策略会立刻被再次 toggle 停止。

### 输出（g1_deploy 发布，订阅示例）

| 话题 | 类型 | 说明 |
|------|------|------|
| `G1Env/env_state_act` | `ByteMultiArray` | 每控制周期状态（msgpack） |
| `WBCPolicy/robot_config` | `ByteMultiArray` | 启动配置（transient_local QoS） |

详情见 `include/output_interface/ros2_output_handler.hpp`。

## 在 g1_deploy 中启用 ROS2

- 启动参数使用 ROS2 输入/输出，或运行 `start_*_policy_ros2.sh`。
- 接口管理器可用 `$` 切换到 ROS2（见 `interface_manager.hpp`）。

## 参考

- 订阅端实现：`include/input_interface/ros2_input_handler.hpp`
- 发布端实现：`include/output_interface/ros2_output_handler.hpp`
- 多阶段运动测试：`tests/test_ros2_control_publisher.cpp`
