#!/bin/bash

# -----------------------------------------------------------------------------
# 脚本名称: enable-ssh-linux.sh
# 功能描述: 检查并尝试在 Linux 系统上安装和启用 SSH 服务 (OpenSSH Server)。
#           支持常见的包管理器 (apt, dnf, yum) 和防火墙工具 (ufw, firewall-cmd)。
# 作者:     AI Assistant & USER
# 版本:     1.0
# -----------------------------------------------------------------------------

echo "Linux SSH 服务启用脚本"
echo "-------------------------"

# --- 1. 检查是否以 root/sudo 权限运行 ---
if [ "$(id -u)" -ne 0 ]; then
  echo "错误：此脚本需要管理员权限 (sudo) 才能运行。"
  echo "请尝试使用 'sudo ./enable-ssh-linux.sh' 来运行。"
  exit 1
fi
echo "权限检查通过。"
echo ""

# --- 2. 安装 OpenSSH Server ---
echo "--- OpenSSH Server 安装 ---"
PACKAGE_MANAGER=""
INSTALL_CMD=""
SSH_SERVER_PACKAGE="openssh-server"

if command -v apt-get &> /dev/null; then
    PACKAGE_MANAGER="apt"
    INSTALL_CMD="apt-get update && apt-get install -y $SSH_SERVER_PACKAGE"
elif command -v dnf &> /dev/null; then
    PACKAGE_MANAGER="dnf"
    INSTALL_CMD="dnf install -y $SSH_SERVER_PACKAGE"
elif command -v yum &> /dev/null; then
    PACKAGE_MANAGER="yum"
    INSTALL_CMD="yum install -y $SSH_SERVER_PACKAGE"
else
    echo "错误：未检测到支持的包管理器 (apt, dnf, yum)。"
    echo "请手动安装 '$SSH_SERVER_PACKAGE'。"
    exit 1
fi

echo "检测到包管理器: $PACKAGE_MANAGER"
echo "正在检查 '$SSH_SERVER_PACKAGE' 是否已安装..."

# 检查 SSH server 是否已安装 (方法可能因发行版而异，这里用一个通用尝试)
# 对于 dpkg (Debian/Ubuntu)
if command -v dpkg &> /dev/null && dpkg -s $SSH_SERVER_PACKAGE &> /dev/null; then
    echo "'$SSH_SERVER_PACKAGE' 已安装 (通过 dpkg)。"
# 对于 rpm (Fedora/RHEL/CentOS)
elif command -v rpm &> /dev/null && rpm -q $SSH_SERVER_PACKAGE &> /dev/null; then
    echo "'$SSH_SERVER_PACKAGE' 已安装 (通过 rpm)。"
else
    echo "'$SSH_SERVER_PACKAGE' 未安装或无法确定状态，正在尝试安装..."
    if eval "sudo $INSTALL_CMD"; then
        echo "'$SSH_SERVER_PACKAGE' 已成功安装。"
    else
        echo "错误：安装 '$SSH_SERVER_PACKAGE' 失败。"
        exit 1
    fi
fi
echo ""

# --- 3. 启用并启动 sshd 服务 ---
echo "--- SSH 服务 (sshd) 配置与启动 ---"
# 服务名称通常是 sshd 或 ssh
SERVICE_NAME="sshd"
if ! systemctl list-units --full -all | grep -q "$SERVICE_NAME.service"; then
    echo "服务 '$SERVICE_NAME' 未找到，尝试使用 'ssh.service'..."
    SERVICE_NAME="ssh"
    if ! systemctl list-units --full -all | grep -q "$SERVICE_NAME.service"; then
        echo "错误：未找到 SSH 服务 ('sshd.service' 或 'ssh.service')。安装可能不完整。"
        exit 1
    fi
fi
echo "将使用服务名: $SERVICE_NAME"

echo "正在启用 '$SERVICE_NAME' 服务 (开机自启)..."
if sudo systemctl enable "$SERVICE_NAME"; then
    echo "'$SERVICE_NAME' 服务已成功启用。"
else
    echo "警告：启用 '$SERVICE_NAME' 服务失败。可能已启用或发生错误。"
fi

echo "正在启动 '$SERVICE_NAME' 服务..."
if sudo systemctl start "$SERVICE_NAME"; then
    echo "'$SERVICE_NAME' 服务已成功启动。"
else
    echo "错误：启动 '$SERVICE_NAME' 服务失败。请检查 'sudo systemctl status $SERVICE_NAME' 和 'journalctl -xeu $SERVICE_NAME' 获取详情。"
    # 尝试重启以防万一
    echo "尝试重启 '$SERVICE_NAME' 服务..."
    sudo systemctl restart "$SERVICE_NAME"
fi

# 检查服务状态
echo "正在检查 '$SERVICE_NAME' 服务状态..."
if sudo systemctl is-active --quiet "$SERVICE_NAME"; then
    echo "'$SERVICE_NAME' 服务正在运行。"
else
    echo "警告：'$SERVICE_NAME' 服务未处于活动状态。请手动检查。"
    sudo systemctl status "$SERVICE_NAME" --no-pager -l
fi
echo ""

# --- 4. 配置防火墙 ---
echo "--- 防火墙配置 ---"
SSH_PORT="22"

if command -v ufw &> /dev/null; then
    echo "检测到 ufw 防火墙。"
    if sudo ufw status | grep -qw "inactive"; then
        echo "ufw 防火墙未激活，无需配置规则。如果需要，请使用 'sudo ufw enable' 激活。"
    else
        echo "正在尝试允许 SSH (端口 $SSH_PORT) 通过 ufw..."
        if sudo ufw allow ssh; then
            echo "ufw 规则已更新以允许 SSH。"
            sudo ufw status verbose
        elif sudo ufw allow $SSH_PORT/tcp; then
            echo "ufw 规则已更新以允许端口 $SSH_PORT/tcp。"
            sudo ufw status verbose
        else
            echo "警告：通过 ufw 允许 SSH 失败。请手动检查 'sudo ufw status'。"
        fi
    fi
elif command -v firewall-cmd &> /dev/null; then
    echo "检测到 firewalld 防火墙。"
    if ! sudo firewall-cmd --state &> /dev/null; then
         echo "firewalld 服务未运行。如果需要，请使用 'sudo systemctl start firewalld' 启动。"
    else
        echo "正在尝试永久允许 ssh 服务或端口 $SSH_PORT/tcp 通过 firewalld..."
        if sudo firewall-cmd --permanent --add-service=ssh && sudo firewall-cmd --reload; then
            echo "firewalld 规则已更新以允许 ssh 服务。"
        elif sudo firewall-cmd --permanent --add-port=$SSH_PORT/tcp && sudo firewall-cmd --reload; then
            echo "firewalld 规则已更新以允许端口 $SSH_PORT/tcp。"
        else
            echo "警告：通过 firewalld 允许 SSH 失败。请手动检查 'sudo firewall-cmd --list-all'。"
        fi
        echo "当前活动的 firewalld 规则："
        sudo firewall-cmd --list-services
        sudo firewall-cmd --list-ports
    fi
else
    echo "未检测到 ufw 或 firewalld。如果系统启用了其他防火墙 (如 iptables)，"
    echo "请确保 TCP 端口 $SSH_PORT (入站) 已被允许。"
fi
echo ""

echo "SSH 服务配置尝试完成。"
echo "请从另一台机器尝试通过 SSH 连接到此计算机以验证。"
echo "例如: ssh $(whoami)@$(hostname -I | awk '{print $1}')"

exit 0
