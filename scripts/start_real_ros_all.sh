SESSION="plc"

sudo jetson_clocks

tmux new-session -d -s "$SESSION" '
    cd gear_sonic_deploy
    echo "y" | bash scripts/start_real_policy_ros2.sh
    '


SESSION="cmdb"

tmux new-session -d -s "$SESSION" '
    cd gear_sonic_deploy
    bash scripts/start_nav2_cmd_vel_bridge.sh
    '