#!/bin/bash
# control-monitor.sh
#
# 一个使用 xset 控制显示器 DPMS (电源管理) 状态的脚本。

# --- 配置 ---
set -e
set -o pipefail

# --- 颜色定义 ---
C_RESET='\033[0m'
C_RED='\033[0;31m'
C_CYAN='\033[0;36m'

# --- 函数定义 ---

function show_usage() {
    echo "用法: $0 <on|off|standby|suspend|status>"
    echo "控制显示器的电源状态。"
    echo
    echo "动作:"
    echo "  on        强制开启显示器。"
    echo "  off       关闭显示器。"
    echo "  standby   将显示器置于待机模式。"
    echo "  suspend   将显示器置于挂起模式。"
    echo "  status    显示当前的 DPMS 设置。"
    echo "  -h, --help  显示此帮助信息。"
}

# --- 主逻辑 ---

# 1. 验证输入和环境
ACTION=$1

if [ "$ACTION" = "-h" ] || [ "$ACTION" = "--help" ]; then
    show_usage
    exit 0
fi

if [ -z "$DISPLAY" ]; then
    echo -e "${C_RED}错误: DISPLAY 环境变量未设置。此脚本只能在图形会话中运行。${C_RESET}" >&2
    exit 1
fi

if ! command -v xset &> /dev/null; then
    echo -e "${C_RED}错误: 'xset' 命令未找到。请确保 xorg-xset 已安装。${C_RESET}" >&2
    exit 1
fi

# 2. 执行动作
case "$ACTION" in
    on|off|standby|suspend)
        printf "${C_CYAN}正在将显示器状态设置为: %s...${C_RESET}\n" "$ACTION"
        xset dpms force "$ACTION"
        echo "操作完成。"
        ;;
    status)
        printf "${C_CYAN}--- 当前 DPMS 状态 ---${C_RESET}\n"
        xset q | grep -A 2 "DPMS"
        ;;
    *)
        echo -e "${C_RED}错误: 无效的动作 '$ACTION'。${C_RESET}" >&2
        show_usage
        exit 1
        ;;
esac
