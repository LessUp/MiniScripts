#!/bin/bash
# Ubuntu防火墙管理工具
# 用法: ./10-firewall-manager.sh [操作]
# 操作: status, enable, disable, list, allow, deny

# 显示帮助信息
show_help() {
  echo "Ubuntu防火墙(ufw)管理工具"
  echo "用法: $0 [操作] [参数]"
  echo "操作:"
  echo "  status         - 显示防火墙状态"
  echo "  enable         - 启用防火墙"
  echo "  disable        - 禁用防火墙"
  echo "  list           - 列出所有规则"
  echo "  allow <端口>   - 允许指定端口 (例如: 80/tcp)"
  echo "  deny <端口>    - 拒绝指定端口 (例如: 80/tcp)"
  echo "  delete <规则号> - 删除指定规则号的规则"
  echo "例如: $0 allow 80/tcp"
}

# 检查ufw是否安装
check_ufw() {
  if ! command -v ufw &> /dev/null; then
    echo "错误: ufw未安装"
    echo "正在尝试安装ufw..."
    sudo apt update
    sudo apt install -y ufw
    
    if [ $? -ne 0 ]; then
      echo "ufw安装失败，请手动安装: sudo apt install -y ufw"
      exit 1
    fi
  fi
}

# 检查是否为root用户
check_root() {
  if [ "$(id -u)" -ne 0 ]; then
    echo "错误: 需要root权限执行此操作"
    echo "请使用 sudo $0 $*"
    exit 1
  fi
}

# 显示防火墙状态
firewall_status() {
  echo "===== 防火墙状态 ====="
  ufw status verbose
}

# 启用防火墙
firewall_enable() {
  echo "===== 启用防火墙 ====="
  echo "y" | ufw enable
  echo "防火墙已启用"
}

# 禁用防火墙
firewall_disable() {
  echo "===== 禁用防火墙 ====="
  echo "y" | ufw disable
  echo "防火墙已禁用"
}

# 列出所有规则
firewall_list() {
  echo "===== 防火墙规则列表 ====="
  ufw status numbered
}

# 允许端口
firewall_allow() {
  if [ -z "$1" ]; then
    echo "错误: 未指定端口"
    echo "用法: $0 allow <端口>"
    exit 1
  fi
  
  PORT="$1"
  echo "===== 允许端口 $PORT ====="
  ufw allow "$PORT"
  echo "规则已添加"
  ufw status | grep "$PORT"
}

# 拒绝端口
firewall_deny() {
  if [ -z "$1" ]; then
    echo "错误: 未指定端口"
    echo "用法: $0 deny <端口>"
    exit 1
  fi
  
  PORT="$1"
  echo "===== 拒绝端口 $PORT ====="
  ufw deny "$PORT"
  echo "规则已添加"
  ufw status | grep "$PORT"
}

# 删除规则
firewall_delete() {
  if [ -z "$1" ]; then
    echo "错误: 未指定规则号"
    echo "用法: $0 delete <规则号>"
    echo "使用 '$0 list' 查看规则号"
    exit 1
  fi
  
  RULE_NUMBER="$1"
  echo "===== 删除规则 $RULE_NUMBER ====="
  echo "y" | ufw delete "$RULE_NUMBER"
  echo "规则已删除"
}

# 主函数
main() {
  # 如果没有参数，显示帮助
  if [ -z "$1" ]; then
    show_help
    exit 1
  fi
  
  # 检查ufw
  check_ufw
  
  # 除了status和list外，其他操作需要root权限
  if [ "$1" != "status" ] && [ "$1" != "list" ]; then
    check_root "$@"
  fi
  
  # 根据参数执行相应功能
  case "$1" in
    "status")
      firewall_status
      ;;
    "enable")
      firewall_enable
      ;;
    "disable")
      firewall_disable
      ;;
    "list")
      firewall_list
      ;;
    "allow")
      firewall_allow "$2"
      ;;
    "deny")
      firewall_deny "$2"
      ;;
    "delete")
      firewall_delete "$2"
      ;;
    *)
      echo "未知操作: $1"
      show_help
      exit 1
      ;;
  esac
}

# 执行主函数
main "$@"
