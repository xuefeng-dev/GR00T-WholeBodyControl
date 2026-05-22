/**
 * @file test_ros2_control_publisher.cpp
 * @brief Publishes msgpack control goals to exercise ROS2 locomotion commands.
 *
 * Topic: ControlPolicy/upper_body_pose (std_msgs/ByteMultiArray)
 *
 * toggle_policy_action is a TOGGLE (flip-flop), NOT "hold to run".
 * Sending it every frame will START then immediately STOP the policy.
 * This test sends exactly ONE start pulse, then only navigate_cmd updates.
 *
 * Expected g1_deploy logs (once):
 *   [ROS2 DEBUG] toggle_policy_action: START control
 *   [Control] DEBUG: operator_state.start=true, transitioning to CONTROL state
 * Do NOT expect a second "STOP control" unless you send toggle again.
 *
 * Terminals (sim):
 *   1. python gear_sonic/scripts/run_sim_loop.py
 *   2. ./scripts/start_sim_policy_ros2.sh   -> wait "Init Done", keep running
 *   3. ./target/release/test_ros2_control_publisher --wait-sec 3
 *
 * Manual start alternative: press ']' in g1_deploy terminal (no toggle in test).
 */

#ifdef HAS_ROS2

#include <rclcpp/rclcpp.hpp>
#include <std_msgs/msg/byte_multi_array.hpp>

#include <msgpack.hpp>

#include <array>
#include <chrono>
#include <cmath>
#include <cstring>
#include <iostream>
#include <string>
#include <thread>
#include <vector>

namespace {

constexpr const char* kTopic = "ControlPolicy/upper_body_pose";
constexpr double kDefaultBaseHeight = 0.78;
constexpr double kPublishHz = 50.0;

constexpr std::array<double, 14> kDefaultWristPose = {
    0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0,
    0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0,
};

struct Phase {
    const char* name;
    std::array<double, 3> navigate_cmd;
    int locomotion_mode;
    double duration_sec;
};

struct TestConfig {
    double wait_sec = 5.0;
    double settle_sec = 2.0;  // after start pulse, before locomotion phases
    double phase_sec = 5.0;
    bool skip_start_pulse = false;
};

std::vector<uint8_t> PackControlGoal(
    const std::array<double, 3>& navigate_cmd,
    double base_height_command,
    int locomotion_mode,
    bool toggle_policy_action,
    double ros_timestamp) {
    msgpack::sbuffer buffer;
    msgpack::packer<msgpack::sbuffer> pk(&buffer);

    const int map_size = toggle_policy_action ? 6 : 5;
    pk.pack_map(map_size);

    pk.pack(std::string("navigate_cmd"));
    pk.pack(std::vector<double>{navigate_cmd[0], navigate_cmd[1], navigate_cmd[2]});

    pk.pack(std::string("wrist_pose"));
    pk.pack(std::vector<double>(kDefaultWristPose.begin(), kDefaultWristPose.end()));

    pk.pack(std::string("base_height_command"));
    pk.pack(base_height_command);

    pk.pack(std::string("locomotion_mode"));
    pk.pack(locomotion_mode);

    pk.pack(std::string("ros_timestamp"));
    pk.pack(ros_timestamp);

    if (toggle_policy_action) {
        pk.pack(std::string("toggle_policy_action"));
        pk.pack(true);
    }

    return std::vector<uint8_t>(buffer.data(), buffer.data() + buffer.size());
}

void Publish(
    const rclcpp::Publisher<std_msgs::msg::ByteMultiArray>::SharedPtr& pub,
    const std::array<double, 3>& navigate_cmd,
    int locomotion_mode,
    bool toggle_policy_action,
    double ros_timestamp) {
    auto payload = PackControlGoal(
        navigate_cmd, kDefaultBaseHeight, locomotion_mode,
        toggle_policy_action, ros_timestamp);

    std_msgs::msg::ByteMultiArray msg;
    msg.data = std::move(payload);
    pub->publish(msg);
}

void PublishHold(
    const rclcpp::Node::SharedPtr& node,
    const rclcpp::Publisher<std_msgs::msg::ByteMultiArray>::SharedPtr& pub,
    const std::array<double, 3>& navigate_cmd,
    int locomotion_mode,
    bool toggle_policy_action,
    double duration_sec) {
    const auto period = std::chrono::duration<double>(1.0 / kPublishHz);
    const auto end_time =
        std::chrono::steady_clock::now() +
        std::chrono::duration<double>(duration_sec);

    while (rclcpp::ok() && std::chrono::steady_clock::now() < end_time) {
        Publish(pub, navigate_cmd, locomotion_mode, toggle_policy_action,
                node->get_clock()->now().seconds());
        rclcpp::spin_some(node);
        std::this_thread::sleep_for(
            std::chrono::duration_cast<std::chrono::nanoseconds>(period));
    }
}

void PrintUsage() {
    std::cout
        << "Usage: test_ros2_control_publisher [options]\n"
        << "  --wait-sec SEC       Wait before publishing (default: 5)\n"
        << "  --settle-sec SEC     Pause after start pulse (default: 2)\n"
        << "  --phase-sec SEC      Per walk/turn/run/idle phase (default: 5)\n"
        << "  --skip-start-pulse   Do not send toggle (use g1_deploy ']' instead)\n"
        << "\n"
        << "toggle_policy_action is sent ONCE only (edge toggle).\n"
        << "Topic: " << kTopic << "\n";
}

int ParseArgs(int argc, char** argv, TestConfig& cfg) {
    for (int i = 1; i < argc; ++i) {
        if (std::strcmp(argv[i], "--wait-sec") == 0 && i + 1 < argc) {
            cfg.wait_sec = std::atof(argv[++i]);
        } else if (std::strcmp(argv[i], "--settle-sec") == 0 && i + 1 < argc) {
            cfg.settle_sec = std::atof(argv[++i]);
        } else if (std::strcmp(argv[i], "--phase-sec") == 0 && i + 1 < argc) {
            cfg.phase_sec = std::atof(argv[++i]);
        } else if (std::strcmp(argv[i], "--skip-start-pulse") == 0) {
            cfg.skip_start_pulse = true;
        } else if (std::strcmp(argv[i], "-h") == 0 ||
                   std::strcmp(argv[i], "--help") == 0) {
            PrintUsage();
            return 2;
        } else {
            std::cerr << "Unknown argument: " << argv[i] << "\n";
            PrintUsage();
            return 1;
        }
    }
    if (cfg.wait_sec < 0.0 || cfg.settle_sec < 0.0 || cfg.phase_sec <= 0.0) {
        std::cerr << "Invalid duration.\n";
        return 1;
    }
    return 0;
}

void RunPhases(
    const rclcpp::Node::SharedPtr& node,
    const rclcpp::Publisher<std_msgs::msg::ByteMultiArray>::SharedPtr& pub,
    const std::vector<Phase>& phases) {
    const auto period = std::chrono::duration<double>(1.0 / kPublishHz);

    for (const auto& phase : phases) {
        std::cout << "[phase] " << phase.name << " (" << phase.duration_sec
                  << " s)\n";
        auto phase_start = std::chrono::steady_clock::now();

        while (rclcpp::ok()) {
            const double elapsed = std::chrono::duration<double>(
                std::chrono::steady_clock::now() - phase_start)
                .count();
            if (elapsed >= phase.duration_sec) {
                break;
            }

            Publish(pub, phase.navigate_cmd, phase.locomotion_mode, false,
                    node->get_clock()->now().seconds());

            static int log_counter = 0;
            if (++log_counter % static_cast<int>(kPublishHz) == 0) {
                std::cout << "  nav=[" << phase.navigate_cmd[0] << ", "
                          << phase.navigate_cmd[1] << ", "
                          << phase.navigate_cmd[2] << "]"
                          << "  mode=" << phase.locomotion_mode
                          << "  t=" << elapsed << "s\n";
            }

            rclcpp::spin_some(node);
            std::this_thread::sleep_for(
                std::chrono::duration_cast<std::chrono::nanoseconds>(period));
        }
        std::cout << "[done] " << phase.name << "\n";
    }
}

}  // namespace

int main(int argc, char** argv) {
    TestConfig cfg;
    const int parse_rc = ParseArgs(argc, argv, cfg);
    if (parse_rc != 0) {
        return parse_rc == 2 ? 0 : 1;
    }

    std::cout << "ROS2 control publisher test\n";
    std::cout << "  topic:       " << kTopic << "\n";
    std::cout << "  wait_sec:    " << cfg.wait_sec << "\n";
    std::cout << "  settle_sec:  " << cfg.settle_sec << "\n";
    std::cout << "  phase_sec:   " << cfg.phase_sec << "\n";
    std::cout << "  start_pulse: " << (cfg.skip_start_pulse ? "no" : "once")
              << "\n";
    std::cout << "  rate:        " << kPublishHz << " Hz\n\n";

    rclcpp::init(argc, argv);
    auto node = rclcpp::Node::make_shared("test_ros2_control_publisher");
    auto pub = node->create_publisher<std_msgs::msg::ByteMultiArray>(kTopic, 10);

    if (cfg.wait_sec > 0.0) {
        std::cout << "Waiting " << cfg.wait_sec
                  << " s — g1_deploy should show 'Init Done'...\n";
        std::this_thread::sleep_for(
            std::chrono::duration<double>(cfg.wait_sec));
    }

    if (!cfg.skip_start_pulse) {
        std::cout << "Sending ONE toggle_policy_action pulse (start)...\n";
        Publish(pub, {0.0, 0.0, 0.0}, 0, true,
                node->get_clock()->now().seconds());
        rclcpp::spin_some(node);
        std::this_thread::sleep_for(std::chrono::milliseconds(50));
        // Hold neutral commands without toggle while planner initializes.
        if (cfg.settle_sec > 0.0) {
            std::cout << "Settling " << cfg.settle_sec
                      << " s (nav=0, no toggle)...\n";
            PublishHold(node, pub, {0.0, 0.0, 0.0}, 0, false, cfg.settle_sec);
        }
    } else {
        std::cout << "Skipped start pulse — start policy manually (e.g. ']').\n";
    }

    const std::vector<Phase> phases = {
        {"slow_walk", {0.35, 0.0, 0.0}, 0, cfg.phase_sec},
        {"fast_walk_run", {0.50, 0.0, 0.0}, 1, cfg.phase_sec},
        {"turn_in_place", {0.0, 0.0, 0.80}, 1, cfg.phase_sec},
        {"run", {0.70, 0.0, 0.0}, 2, cfg.phase_sec},
        {"idle", {0.0, 0.0, 0.0}, 1, cfg.phase_sec},
    };

    RunPhases(node, pub, phases);

    std::cout << "\nDone. Publishing idle 2 s (no toggle), then exit.\n";
    PublishHold(node, pub, {0.0, 0.0, 0.0}, 1, false, 2.0);

    rclcpp::shutdown();
    return 0;
}

#else

int main(int argc, char** argv) {
    (void)argc;
    (void)argv;
    std::cerr << "ROS2 support not compiled. Build with ROS2 + msgpack.\n";
    return 1;
}

#endif
