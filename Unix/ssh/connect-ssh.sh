#!/bin/bash
# ======================================================================
# connect-ssh.sh
# 通过交互式菜单连接到预定义的 SSH 主机，支持 fzf 模糊搜索。
# ======================================================================
set -e
set -o pipefail

CONFIG_FILE="$HOME/.ssh/config"
LIST_ONLY=false

C_RESET='\033[0m'
C_CYAN='\033[0;36m'
C_YELLOW='\033[0;33m'

show_usage() {
  echo "用法: $0 [选项]"
  echo "通过交互式菜单连接到 SSH 主机。"
  echo
  echo "选项:"
  echo "  -c, --config <文件>   指定 SSH 主机配置文件的路径 (默认为: $CONFIG_FILE)。"
  echo "  -l, --list            只列出所有可用的主机，不进行连接。"
  echo "  -h, --help            显示此帮助信息。"
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
      -c|--config)
        CONFIG_FILE="$2"
        shift; shift;;
      -l|--list)
        LIST_ONLY=true
        shift;;
      -h|--help)
        show_usage
        exit 0
        ;;
      *)
        echo "未知选项: $1"
        show_usage
        exit 1
        ;;
    esac
  done
}

main() {
  parse_args "$@"

  if [ ! -f "$CONFIG_FILE" ]; then
    echo "错误: 配置文件未找到: $CONFIG_FILE" >&2
    exit 1
  fi

  local hosts
  hosts=$(grep -E '^Host ' "$CONFIG_FILE" | awk '{print $2}' | grep -v '*')

  if [ -z "$hosts" ]; then
    echo "在 '$CONFIG_FILE' 中没有找到任何有效的主机定义。"
    exit 1
  fi

  if [ "$LIST_ONLY" = true ]; then
    echo "可用的 SSH 主机:"
    echo -e "$C_CYAN$hosts$C_RESET"
    exit 0
  fi

  local selected_host
  selected_host=$(echo "$hosts" | fzf --height 40% --reverse --prompt="请选择要连接的主机: ")

  if [ -n "$selected_host" ]; then
    echo -e "${C_YELLOW}正在连接到: $selected_host...${C_RESET}"
    ssh "$selected_host"
  else
    echo "未选择任何主机。"
  fi
}

main "$@"
