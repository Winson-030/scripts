#!/bin/bash

# Docker 管理脚本 (多语言版)
# 功能：安装/卸载 Docker CE，添加用户到 docker 组
# 兼容：Ubuntu 20.04+ / Debian 10+
# 用法：sudo ./docker-manage.sh [install|remove|add] [username]

set -eo pipefail

# 区域检测函数
detect_lang() {
    # 优先检查 LANG 变量
    if [[ $LANG == zh_CN* ]]; then
        LANG_TYPE="zh"
        return
    fi

    # 其次检查时区设置
    if [[ -f /etc/timezone ]] && grep -q -E 'Asia/(Shanghai|Chongqing|Harbin|Urumqi)' /etc/timezone; then
        LANG_TYPE="zh"
        return
    fi

    # 默认为英文
    LANG_TYPE="en"
}

# 初始化语言设置
detect_lang

# 配置参数
DOCKER_GPG_PATH="/etc/apt/keyrings/docker.gpg"
DOCKER_SOURCE_LIST="/etc/apt/sources.list.d/docker.list"
DOCKER_PACKAGES="docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin"
REQUIRED_PACKAGES="apt-transport-https curl ca-certificates software-properties-common"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

# 多语言消息函数
error_msg() {
    local zh_msg="$1"
    local en_msg="$2"
    if [[ $LANG_TYPE == "zh" ]]; then
        echo -e "${RED}[错误] $zh_msg${NC}" >&2
    else
        echo -e "${RED}[Error] $en_msg${NC}" >&2
    fi
}

success_msg() {
    local zh_msg="$1"
    local en_msg="$2"
    if [[ $LANG_TYPE == "zh" ]]; then
        echo -e "${GREEN}[成功] $zh_msg${NC}"
    else
        echo -e "${GREEN}[Success] $en_msg${NC}"
    fi
}

info_msg() {
    local zh_msg="$1"
    local en_msg="$2"
    if [[ $LANG_TYPE == "zh" ]]; then
        echo -e "${GREEN}[信息] $zh_msg${NC}"
    else
        echo -e "${GREEN}[Info] $en_msg${NC}"
    fi
}

warning_msg() {
    local zh_msg="$1"
    local en_msg="$2"
    if [[ $LANG_TYPE == "zh" ]]; then
        echo -e "${YELLOW}[提示] $zh_msg${NC}"
    else
        echo -e "${YELLOW}[Notice] $en_msg${NC}"
    fi
}

# 错误处理
error_exit() {
    error_msg "$1" "$2"
    exit 1
}

# 检测 root 权限
check_root() {
    if [[ $EUID -ne 0 ]]; then
        error_exit "请使用 sudo 或 root 用户运行此脚本" "This script must be run as root or with sudo"
    fi
}

# 检查 Docker 是否已安装
check_docker_installed() {
    if ! command -v docker &>/dev/null; then
        error_exit "Docker 未安装，请先执行安装操作" "Docker is not installed, please install first"
    fi
}

# 添加用户到 docker 组
add_user_to_docker_group() {
    local username=$1

    info_msg "正在添加用户到 docker 组..." "Adding user to docker group..."

    # 检查用户是否存在
    if ! id "$username" &>/dev/null; then
        error_exit "用户 $username 不存在" "User $username does not exist"
    fi

    # 检查是否已在组中
    if groups "$username" | grep -q '\bdocker\b'; then
        warning_msg "用户 $username 已在 docker 组中" "User $username is already in docker group"
        return
    fi

    # 执行添加操作
    usermod -aG docker "$username" || error_exit "用户组添加失败" "Failed to add user to group"
    success_msg "用户 $username 已加入 docker 组" "User $username added to docker group"
    warning_msg "需要重新登录或执行 'newgrp docker' 生效" "Please re-login or run 'newgrp docker' to apply changes"
}

# 安装 Docker
install_docker() {
    local username=$1

    info_msg "开始安装 Docker..." "Starting Docker installation..."

    # 安装前置依赖
    apt-get update -qq
    apt-get install -y -qq $REQUIRED_PACKAGES || error_exit "依赖安装失败" "Dependency installation failed"

    # 添加 Docker GPG 密钥
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
    gpg --dearmor -o "$DOCKER_GPG_PATH" || error_exit "GPG 密钥添加失败" "Failed to add GPG key"

    # 添加软件源
    echo "deb [arch=$(dpkg --print-architecture) signed-by=$DOCKER_GPG_PATH] \
    https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
    tee "$DOCKER_SOURCE_LIST" > /dev/null || error_exit "软件源添加失败" "Failed to add repository"

    # 安装 Docker
    apt-get update -qq
    apt-get install -y -qq $DOCKER_PACKAGES || error_exit "Docker 安装失败" "Docker installation failed"

    # 启动服务
    systemctl enable --now docker > /dev/null 2>&1 || error_exit "服务启动失败" "Service startup failed"

    # 添加用户到 docker 组
    if [[ -n "$username" ]]; then
        add_user_to_docker_group "$username"
    fi

    success_msg "Docker 已成功安装" "Docker installed successfully"
}

# 卸载 Docker
remove_docker() {
    local username=$1

    warning_msg "开始卸载 Docker..." "Starting Docker uninstallation..."

    # 停止服务
    systemctl stop docker.socket docker.service > /dev/null 2>&1 || true

    # 移除软件包
    apt-get purge -y -qq $DOCKER_PACKAGES || error_exit "软件包卸载失败" "Package removal failed"

    # 清理配置
    rm -f "$DOCKER_SOURCE_LIST" "$DOCKER_GPG_PATH"
    apt-get update -qq

    # 移除用户组
    if [[ -n "$username" ]]; then
        if id "$username" &>/dev/null; then
            deluser "$username" docker > /dev/null 2>&1 || true
            info_msg "用户 $username 已从 docker 组移除" "User $username removed from docker group"
        fi
    fi

    # 清理残留文件
    rm -rf /var/lib/docker /etc/docker
    find /etc/apt -name "*docker*" -exec rm -f {} \;

    success_msg "Docker 已彻底卸载" "Docker completely removed"
}

# 显示使用帮助
show_usage() {
    if [[ $LANG_TYPE == "zh" ]]; then
        echo "用法:"
        echo "  安装: sudo $0 install [用户名]"
        echo "  卸载: sudo $0 remove [用户名]"
        echo "  添加用户: sudo $0 add [用户名]"
        echo "示例:"
        echo "  sudo $0 install john  # 安装并添加用户"
        echo "  sudo $0 remove john   # 卸载并移除用户"
        echo "  sudo $0 add mary      # 仅添加用户到 docker 组"
    else
        echo "Usage:"
        echo "  Install: sudo $0 install [username]"
        echo "  Remove: sudo $0 remove [username]"
        echo "  Add user: sudo $0 add [username]"
        echo "Examples:"
        echo "  sudo $0 install john  # Install and add user"
        echo "  sudo $0 remove john   # Uninstall and remove user"
        echo "  sudo $0 add mary      # Add user to docker group only"
    fi
}

# 主函数
main() {
    check_root

    local action=$1
    local username=$2

    case "$action" in
        install)
            install_docker "$username"
            ;;
        remove)
            remove_docker "$username"
            ;;
        add)
            check_docker_installed
            if [[ -z "$username" ]]; then
                error_exit "必须指定要添加的用户名" "Username must be specified"
            fi
            add_user_to_docker_group "$username"
            ;;
        *)
            show_usage
            exit 1
            ;;
    esac
}

main "$@"
