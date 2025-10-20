#!/bin/bash
# show-system-info.sh
#
# 显示一个结构化的系统硬件和软件信息摘要。

# --- 配置 ---
set -e
set -o pipefail

# --- 默认值 ---
SHOW_ALL=true
SHOW_OS=false
SHOW_CPU=false
SHOW_MEM=false
SHOW_DISK=false

# --- 颜色定义 ---
C_RESET='\033[0m'
C_BOLD='\033[1m'
C_CYAN='\033[0;36m'
C_YELLOW='\033[0;33m'

# --- 函数定义 ---

function show_usage() {
    echo "用法: $0 [选项]"
    echo "显示一个全面的系统信息摘要。"
    echo
    echo "选项:"
    echo "  --os          只显示操作系统信息。"
    echo "  --cpu         只显示 CPU 信息。"
    echo "  --mem         只显示内存使用情况。"
    echo "  --disk        只显示磁盘使用情况。"
    echo "  -h, --help    显示此帮助信息。"
    echo
    echo "如果没有提供选项，将显示所有信息。"
}

# --- 参数解析 ---
if [ $# -gt 0 ]; then SHOW_ALL=false; fi
while [[ $# -gt 0 ]]; do
    case $1 in
        --os) SHOW_OS=true; shift;; 
        --cpu) SHOW_CPU=true; shift;; 
        --mem) SHOW_MEM=true; shift;; 
        --disk) SHOW_DISK=true; shift;; 
        -h|--help) show_usage; exit 0;; 
        -*) echo "错误: 未知选项: $1" >&2; show_usage; exit 1;; 
    esac
done

# --- 显示函数 ---

function display_os_info() {
    printf "${C_BOLD}${C_CYAN}--- 操作系统 ---${C_RESET}\n"
    printf "${C_YELLOW}%-12s${C_RESET} %s\n" "主机名:" "$(hostname)"
    if [ -f /etc/os-release ]; then
        # shellcheck source=/dev/null
        . /etc/os-release
        printf "${C_YELLOW}%-12s${C_RESET} %s\n" "发行版:" "$PRETTY_NAME"
    else
        printf "${C_YELLOW}%-12s${C_RESET} %s\n" "发行版:" "$(uname -s)"
    fi
    printf "${C_YELLOW}%-12s${C_RESET} %s\n" "内核:" "$(uname -r)"
    printf "${C_YELLOW}%-12s${C_RESET} %s\n" "运行时间:" "$(uptime -p)"
}

function display_cpu_info() {
    printf "\n${C_BOLD}${C_CYAN}--- CPU 信息 ---${C_RESET}\n"
    if command -v lscpu &> /dev/null; then
        lscpu | grep -E '^(Architecture|CPU\(s\)|Model name|Vendor ID)'
    else
        grep 'model name' /proc/cpuinfo | uniq | cut -d ':' -f 2 | sed -e 's/^[ \t]*//'
    fi
}

function display_memory_info() {
    printf "\n${C_BOLD}${C_CYAN}--- 内存使用情况 ---${C_RESET}\n"
    free -h
}

function display_disk_info() {
    printf "\n${C_BOLD}${C_CYAN}--- 磁盘使用情况 ---${C_RESET}\n"
    # 排除 tmpfs 和 devtmpfs 以减少噪音
    df -h -x tmpfs -x devtmpfs
}

# --- 主逻辑 ---

if [ "$SHOW_ALL" = true ] || [ "$SHOW_OS" = true ]; then
    display_os_info
fi

if [ "$SHOW_ALL" = true ] || [ "$SHOW_CPU" = true ]; then
    display_cpu_info
fi

if [ "$SHOW_ALL" = true ] || [ "$SHOW_MEM" = true ]; then
    display_memory_info
fi

if [ "$SHOW_ALL" = true ] || [ "$SHOW_DISK" = true ]; then
    display_disk_info
fi
