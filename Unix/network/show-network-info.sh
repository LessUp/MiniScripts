#!/bin/bash
# show-network-info.sh
#
# 一个用于显示全面网络信息的仪表盘脚本。

# --- 配置 ---
set -e
set -o pipefail

# --- 默认值 ---
SHOW_ALL=true
SHOW_IP=false
SHOW_PORTS=false
SHOW_ROUTES=false
SHOW_DNS=false

# --- 颜色定义 ---
C_RESET='\033[0m'
C_BOLD='\033[1m'
C_CYAN='\033[0;36m'
C_YELLOW='\033[0;33m'

# --- 函数定义 ---

function show_usage() {
    echo "用法: $0 [选项]"
    echo "显示一个全面的网络信息仪表盘。"
    echo
    echo "选项:"
    echo "  --ip          只显示公网和本地 IP 地址。"
    echo "  --ports       只显示监听的端口。"
    echo "  --routes      只显示路由表。"
    echo "  --dns         只显示 DNS 服务器。"
    echo "  -h, --help    显示此帮助信息。"
    echo
    echo "如果没有提供选项，将显示所有信息。"
}

# --- 参数解析 ---
if [ $# -gt 0 ]; then SHOW_ALL=false; fi
while [[ $# -gt 0 ]]; do
    case $1 in
        --ip) SHOW_IP=true; shift;; 
        --ports) SHOW_PORTS=true; shift;; 
        --routes) SHOW_ROUTES=true; shift;; 
        --dns) SHOW_DNS=true; shift;; 
        -h|--help) show_usage; exit 0;; 
        -*) echo "错误: 未知选项: $1" >&2; show_usage; exit 1;; 
    esac
done

# --- 显示函数 ---

function display_ip_addresses() {
    printf "${C_BOLD}${C_CYAN}--- IP 地址信息 ---${C_RESET}\n"
    # 公网 IP
    if command -v curl &> /dev/null; then
        printf "${C_YELLOW}公网 IP:${C_RESET} %s\n" "$(curl -s ifconfig.me || echo '无法获取')"
    fi
    # 本地接口
    printf "${C_YELLOW}本地网络接口:${C_RESET}\n"
    ip -c addr show | grep -E "inet |inet6 "
}

function display_listening_ports() {
    printf "\n${C_BOLD}${C_CYAN}--- 正在监听的端口 ---${C_RESET}\n"
    if command -v ss &> /dev/null; then
        ss -tulnp
    elif command -v netstat &> /dev/null; then
        netstat -tulnp
    else
        echo "错误: 未找到 'ss' 或 'netstat' 命令。"
    fi
}

function display_routing_table() {
    printf "\n${C_BOLD}${C_CYAN}--- 路由表 ---${C_RESET}\n"
    ip route show
}

function display_dns_servers() {
    printf "\n${C_BOLD}${C_CYAN}--- DNS 服务器 ---${C_RESET}\n"
    if [ -r /etc/resolv.conf ]; then
        grep '^nameserver' /etc/resolv.conf
    else
        echo "无法读取 /etc/resolv.conf"
    fi
}

# --- 主逻辑 ---

if [ "$SHOW_ALL" = true ] || [ "$SHOW_IP" = true ]; then
    display_ip_addresses
fi

if [ "$SHOW_ALL" = true ] || [ "$SHOW_PORTS" = true ]; then
    display_listening_ports
fi

if [ "$SHOW_ALL" = true ] || [ "$SHOW_ROUTES" = true ]; then
    display_routing_table
fi

if [ "$SHOW_ALL" = true ] || [ "$SHOW_DNS" = true ]; then
    display_dns_servers
fi
