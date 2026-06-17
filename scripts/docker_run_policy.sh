#!/bin/bash
set -euo pipefail

# 基于 g1-deploy-dev 镜像启动一次性容器，执行命令后自动删除
#
# 用法:
#   ./scripts/docker_run_policy.sh [OPTIONS] [--] <command> [args...]
#
# 选项:
#   --build-image   镜像不存在时自动构建 g1-deploy-dev
#   -h, --help      显示帮助
#
# 示例:
#   ./scripts/docker_run_policy.sh bash scripts/start_sim_policy_motion_file.sh
#   ./scripts/docker_run_policy.sh -- bash scripts/start_sim_policy_motion_file.sh \
#       --motion-data ../sample_data/other/ sim

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
DEPLOY_ROOT="${REPO_ROOT}/gear_sonic_deploy"
DOCKER_DIR="${DEPLOY_ROOT}/docker"

IMAGE_NAME="${G1_DEPLOY_IMAGE:-g1-deploy-dev}"
WORKDIR_IN_CONTAINER="/workspace/repo"

BUILD_IMAGE=false
USER_CMD=()

show_help() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS] [--] <command> [args...]

Run a one-shot g1-deploy-dev container; it is removed when the command exits.
Working directory in container: ${WORKDIR_IN_CONTAINER}

Options:
  --build-image   Build image ${IMAGE_NAME} if missing
  -h, --help      Show this help

Environment:
  G1_DEPLOY_IMAGE     Docker image name (default: g1-deploy-dev)
  TensorRT_ROOT       Host TensorRT path mounted to /opt/TensorRT

Examples:
  $(basename "$0") bash scripts/start_sim_policy_motion_file.sh
  $(basename "$0") bash scripts/start_sim_policy_motion_file.sh --motion-data ../sample_data/Kimodo-SOMA-RP-v1/g1_deploy/ sim
  $(basename "$0") -- bash -lc 'cd gear_sonic_deploy && just build'
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --build-image)
            BUILD_IMAGE=true
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        --)
            shift
            USER_CMD+=("$@")
            break
            ;;
        *)
            USER_CMD+=("$1")
            shift
            ;;
    esac
done

ensure_image() {
    if docker image inspect "${IMAGE_NAME}" >/dev/null 2>&1; then
        return 0
    fi

    if [[ "${BUILD_IMAGE}" != true ]]; then
        echo "Error: Docker image '${IMAGE_NAME}' not found." >&2
        echo "Run with --build-image or build via:" >&2
        echo "  ${DOCKER_DIR}/run-ros2-dev.sh" >&2
        exit 1
    fi

    echo "Building Docker image: ${IMAGE_NAME}"
    docker build --network host \
        -f "${DOCKER_DIR}/Dockerfile.ros2" \
        -t "${IMAGE_NAME}" \
        "${DEPLOY_ROOT}" \
        --build-arg CUDA_VERSION=12.4.1 \
        --build-arg CUDA_BASE_IMAGE=nvidia/cuda
}

gpu_settings() {
    if docker info 2>/dev/null | grep -q "Runtimes.*nvidia"; then
        echo "--gpus all"
    elif command -v nvidia-smi >/dev/null 2>&1; then
        echo "--gpus all"
    else
        echo ""
    fi
}

tensorrt_mount() {
    if [[ -n "${TensorRT_ROOT:-}" && -d "${TensorRT_ROOT}" ]]; then
        echo "-v ${TensorRT_ROOT}:/opt/TensorRT:ro"
    fi
}

x11_settings() {
    if [[ -n "${DISPLAY:-}" ]]; then
        echo "-e DISPLAY=${DISPLAY} -v /tmp/.X11-unix:/tmp/.X11-unix"
    fi
}

run_in_container() {
    if [[ ${#USER_CMD[@]} -eq 0 ]]; then
        echo "Error: no command specified." >&2
        echo >&2
        show_help >&2
        exit 1
    fi

    local inner=""
    local arg
    for arg in "${USER_CMD[@]}"; do
        inner+=" $(printf '%q' "${arg}")"
    done
    inner="${inner# }"

    local -a run_args=(docker run --rm)
    if [[ -t 0 && -t 1 ]]; then
        run_args+=(-it)
    else
        run_args+=(-i)
    fi

    run_args+=(
        --network host
        -v "${REPO_ROOT}:${WORKDIR_IN_CONTAINER}:rw"
        -e RMW_IMPLEMENTATION=rmw_fastrtps_cpp
        -e ROS_DOMAIN_ID=0
        -e NVIDIA_VISIBLE_DEVICES=all
        -e NVIDIA_DRIVER_CAPABILITIES=compute,utility,graphics
        -w "${WORKDIR_IN_CONTAINER}"
    )

    local gpu
    gpu="$(gpu_settings)"
    if [[ -n "${gpu}" ]]; then
        # shellcheck disable=SC2206
        run_args+=(${gpu})
    fi

    local trt
    trt="$(tensorrt_mount)"
    if [[ -n "${trt}" ]]; then
        # shellcheck disable=SC2206
        run_args+=(${trt})
    fi

    local x11
    x11="$(x11_settings)"
    if [[ -n "${x11}" ]]; then
        # shellcheck disable=SC2206
        run_args+=(${x11})
    fi

    run_args+=(
        "${IMAGE_NAME}"
        bash -lc "${inner}"
    )

    echo "Running one-shot container (${IMAGE_NAME}): ${USER_CMD[*]}"
    "${run_args[@]}"
}

ensure_image
run_in_container
