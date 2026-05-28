# MuJoCo ROS2 位姿接口说明

本文档说明 `run_sim_loop_ros.py` 提供的 ROS2 位姿发布接口，  
用于将仿真中机器人 base 的位置与姿态实时发布给其它节点。

## 1. 功能概述

- 启动 MuJoCo 仿真循环。
- 同时启动 ROS2 节点，周期发布机器人 base 位姿。
- 消息类型：`geometry_msgs/msg/PoseStamped`。
- 默认话题：`/mujoco/base_pose`。

> 代码入口：`gear_sonic/scripts/run_sim_loop_ros.py`

## 2. 启动方式

### 2.1 使用现成脚本

```bash
bash scripts/start_sim_mujoco_ros.sh
```

当前脚本内容会：
- `source .venv_sim/bin/activate`
- 执行 `python gear_sonic/scripts/run_sim_loop_ros.py`

### 2.2 直接命令行启动（推荐）

```bash
python3 gear_sonic/scripts/run_sim_loop_ros.py \
  --ros2_pose_topic /mujoco/base_pose \
  --ros2_pose_frame_id world \
  --ros2_pose_publish_hz 50
```

## 3. ROS2 接口定义

### 发布话题

- Topic: `ros2_pose_topic`（默认 `/mujoco/base_pose`）
- Type: `geometry_msgs/msg/PoseStamped`
- Frame: `header.frame_id = ros2_pose_frame_id`（默认 `world`）
- 频率: `ros2_pose_publish_hz`（默认 `50.0` Hz）

### 字段语义

- `pose.position.{x,y,z}`：机器人 base 在世界系的位置（米）。
- `pose.orientation.{x,y,z,w}`：机器人 base 姿态四元数（ROS 顺序）。
- `header.stamp`：ROS2 当前时间戳。

### 四元数约定

- MuJoCo 内部：`[w, x, y, z]`
- ROS 消息：`[x, y, z, w]`

脚本内部已经完成顺序转换，订阅端无需再次转换。

## 4. 可配置参数（CLI）

以下参数定义在 `SimLoopConfig`：

- `--ros2_pose_topic`  
  位姿发布话题名，默认：`/mujoco/base_pose`
- `--ros2_pose_frame_id`  
  `PoseStamped.header.frame_id`，默认：`world`
- `--ros2_pose_publish_hz`  
  发布频率（Hz），默认：`50.0`

示例：

```bash
python3 gear_sonic/scripts/run_sim_loop_ros.py \
  --ros2_pose_topic /robot/base_pose \
  --ros2_pose_frame_id map \
  --ros2_pose_publish_hz 100
```

## 5. 订阅与验证

查看话题：

```bash
ros2 topic list | rg base_pose
```

查看消息：

```bash
ros2 topic echo /mujoco/base_pose
```

查看频率：

```bash
ros2 topic hz /mujoco/base_pose
```

## 6. 常见问题

### Q1: 启动时报 DDS/接口相关错误

如果出现类似：
- `selected interface "lo" is not multicast-capable`
- `ChannelFactory ... init error`

通常是网络接口与 DDS 配置不匹配。  
建议检查运行参数中的 `--interface` 以及机器网卡状态。

### Q2: 结束进程时出现 ROS2 异常栈

在外部强制终止（如 `timeout`）时，  
可能出现 `ExternalShutdownException`，属于退出路径现象。

## 7. 适用范围

当前接口只发布 **base 位姿**。  
若需要速度、IMU、关节状态、TF 广播，请在此基础上扩展。
