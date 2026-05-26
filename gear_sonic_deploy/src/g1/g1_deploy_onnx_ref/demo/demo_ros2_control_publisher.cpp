/**
 * @file demo_ros2_control_publisher.cpp
 * @brief 最小 ROS2 控制接口示例（面向 g1_deploy）。
 *
 * g1_deploy 订阅话题：
 *   ControlPolicy/upper_body_pose  (std_msgs/msg/ByteMultiArray)
 * 载荷为 msgpack 编码的 map，见 PackControlGoal()。
 *
 * 策略启动：在 g1_deploy 终端按 ']'（start_sim_policy_ros2.sh），无需发 toggle。
 * 本 demo 只发布 navigate_cmd 等运动指令。
 *
 * 运行前请先启动 g1_deploy（ROS2 模式），例如：
 *   ./scripts/start_sim_policy_ros2.sh
 * 在 g1_deploy 终端按 ']' 启动策略后，再运行本 demo：
 *   ./target/release/demo_ros2_control_publisher
 */

#ifdef HAS_ROS2

#include <rclcpp/rclcpp.hpp>
#include <std_msgs/msg/byte_multi_array.hpp>

#include <msgpack.hpp>

#include <array>
#include <chrono>
#include <iostream>
#include <string>
#include <thread>
#include <vector>

namespace {

constexpr std::array<double, 14> kDefaultWristPose = {
    0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0,
    0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0,
};

/// 本 demo 用到的控制目标字段（经 PackControlGoal 打成 msgpack map）。
/// 完整协议还包含 wrist_pose 等，见 ros2_input_handler.hpp 中的 ControlGoalMsg。
struct ControlGoal {
    /// 导航速度 [lin_vel_x, lin_vel_y, ang_vel_z]：前进/侧移 m/s，绕 z 角速度 rad/s。
    std::array<double, 3> navigate_cmd{0.0, 0.0, 0.0};
    /// 期望基座高度（米），有效范围约 0.1–0.88；0.72–0.88 时配合 locomotion_mode 行走。
    double base_height = 0.78;
    /// 步态档位：0=慢走，1=快走，2=跑（仅在 base_height ≥ 0.72 且有移动量时生效）。
    int locomotion_mode = 0;
    /// ROS 时间戳（秒），供 g1_deploy 与其它组件对齐；建议用 node clock。
    double ros_timestamp = 0.0;
    /// 边沿触发：true 时切换策略启停（翻转，非按住）。本 demo 默认不发，用终端 ']' 启动。
    bool toggle_policy_action = false;
};

std::vector<uint8_t> PackControlGoal(const ControlGoal& goal) {
    msgpack::sbuffer buffer;
    msgpack::packer<msgpack::sbuffer> pk(&buffer);

    const int map_size = goal.toggle_policy_action ? 6 : 5;
    pk.pack_map(map_size);

    pk.pack(std::string("navigate_cmd"));
    pk.pack(std::vector<double>{
        goal.navigate_cmd[0], goal.navigate_cmd[1], goal.navigate_cmd[2]});

    pk.pack(std::string("wrist_pose"));
    pk.pack(std::vector<double>(kDefaultWristPose.begin(), kDefaultWristPose.end()));

    pk.pack(std::string("base_height_command"));
    pk.pack(goal.base_height);

    pk.pack(std::string("locomotion_mode"));
    pk.pack(goal.locomotion_mode);

    pk.pack(std::string("ros_timestamp"));
    pk.pack(goal.ros_timestamp);

    if (goal.toggle_policy_action) {
        pk.pack(std::string("toggle_policy_action"));
        pk.pack(true);
    }

    return {buffer.data(), buffer.data() + buffer.size()};
}

std_msgs::msg::ByteMultiArray MakeRosMessage(const ControlGoal& goal) {
    std_msgs::msg::ByteMultiArray msg;
    msg.data = PackControlGoal(goal);
    return msg;
}

void Publish(
    const rclcpp::Publisher<std_msgs::msg::ByteMultiArray>::SharedPtr& pub,
    const rclcpp::Node::SharedPtr& node,
    const ControlGoal& goal) {
    pub->publish(MakeRosMessage(goal));
    rclcpp::spin_some(node);
}

}  // namespace

int main(int argc, char** argv) {
    const std::string topic = "ControlPolicy/upper_body_pose";
    const double publish_hz = 50.0;
    const double forward_speed = 0.35;
    const int locomotion_mode = 0;  // 0=慢走, 1=快走, 2=跑

    std::cout << "=== ROS2 控制接口 Demo ===\n";
    std::cout << "发布话题: " << topic << "\n";
    std::cout << "消息类型: std_msgs/msg/ByteMultiArray (data 为 msgpack 字节)\n\n";

    rclcpp::init(argc, argv);
    auto node = rclcpp::Node::make_shared("demo_ros2_control_publisher");
    auto pub = node->create_publisher<std_msgs::msg::ByteMultiArray>(topic, 10);

    const auto period = std::chrono::duration<double>(1.0 / publish_hz);

    const double wait_sec = 3.0;
    std::cout << "等待 " << wait_sec << " s，请确认 g1_deploy 已就绪...\n";
    std::cout << "请在 g1_deploy 终端按 ']' 启动策略，再等待运动指令...\n";
    std::this_thread::sleep_for(std::chrono::duration<double>(wait_sec));

    // 持续发布前进指令
    const double walk_duration_sec = 8.0;
    std::cout << "持续发布前进指令 " << walk_duration_sec << " s"
              << " @ " << publish_hz << " Hz\n";
    std::cout << "  navigate_cmd = [" << forward_speed << ", 0, 0]\n";
    std::cout << "  locomotion_mode = " << locomotion_mode << "\n\n";

    const auto end_time = std::chrono::steady_clock::now()
        + std::chrono::duration<double>(walk_duration_sec);
    int tick = 0;

    while (rclcpp::ok() && std::chrono::steady_clock::now() < end_time) {
        const double ros_timestamp = node->get_clock()->now().seconds();
        Publish(pub, node, ControlGoal{
            .navigate_cmd = {forward_speed, 0.0, 0.0},
            .locomotion_mode = locomotion_mode,
            .ros_timestamp = ros_timestamp,
        });

        if (++tick % static_cast<int>(publish_hz) == 0) {
            std::cout << "  发布中... t=" << ros_timestamp << " s\n";
        }

        std::this_thread::sleep_for(
            std::chrono::duration_cast<std::chrono::nanoseconds>(period));
    }

    // 零速度收尾
    std::cout << "\n发送 2 s 零速度后退出（紧急停止：g1_deploy 终端按 O/o）\n";
    const auto idle_end = std::chrono::steady_clock::now()
        + std::chrono::duration<double>(2.0);
    while (rclcpp::ok() && std::chrono::steady_clock::now() < idle_end) {
        Publish(pub, node, ControlGoal{
            .navigate_cmd = {0.0, 0.0, 0.0},
            .locomotion_mode = locomotion_mode,
            .ros_timestamp = node->get_clock()->now().seconds(),
        });
        std::this_thread::sleep_for(
            std::chrono::duration_cast<std::chrono::nanoseconds>(period));
    }

    rclcpp::shutdown();
    std::cout << "Demo 结束。\n";
    return 0;
}

#else

int main(int argc, char** argv) {
    (void)argc;
    (void)argv;
    std::cerr << "未编译 ROS2 支持。请设置 HAS_ROS2=1 并安装 ROS2、msgpack 后重新构建。\n";
    return 1;
}

#endif
