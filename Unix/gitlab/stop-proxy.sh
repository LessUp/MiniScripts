#!/bin/bash
# =============================================================================
# GitLab SOCKS 代理停止脚本
#
# 设计说明:
#   - 平台: macOS, Linux, WSL。
#   - 行为: 停止通过 PID 文件记录的 SSH 代理进程，清理 PID 文件，并删除条件代理文件（不修改 include.path）。
# =============================================================================

# --- 1. 定义核心变量 ---
PID_FILE="./.proxy-pid"

# --- 1.1 工具函数 ---
find_pid_by_port() {
    # 基于 ssh 启动参数中的转发参数精确匹配端口，兼容 -D 与 DynamicForward 两种形式
    pgrep -f "ssh.*(DynamicForward=127\\.0\\.0\\.1:${1}|-D[[:space:]]*127\\.0\\.0\\.1:${1})" | head -n 1
}

# --- 2. 脚本主逻辑 ---
echo "========================================="
echo "==  GitLab SOCKS 代理停止程序 (v3)    =="
echo "========================================="
echo ""

# --- 步骤 1: 删除 Git 条件代理配置文件 ---
echo "[*] 步骤 1: 删除 Git 条件代理配置文件..."
GIT_PROXY_CONFIG_FILE="$HOME/.gitconfig-bgi-proxy-v3"
if [ -f "$GIT_PROXY_CONFIG_FILE" ]; then
    echo "    正在删除临时代理配置文件..."
    rm -f "$GIT_PROXY_CONFIG_FILE"
else
    echo "    ℹ️ 未找到临时代理配置文件。"
fi

# --- 步骤 1.1: 清理全局 include.path 中的临时配置 ---
echo "    正在清理全局 include.path..."
if command -v git >/dev/null 2>&1; then
    if git config --global --unset include.path "$GIT_PROXY_CONFIG_FILE" 2>/dev/null; then
        echo "    已移除 include.path -> $GIT_PROXY_CONFIG_FILE"
    else
        echo "    未在 include.path 中找到该项或已移除。"
    fi
else
    echo "    警告: 未找到 git 命令，跳过 include.path 清理。"
fi

# --- 步骤 2: 停止代理进程并清理 PID 文件 ---
echo ""
echo "[*] 步骤 2: 停止代理进程..."
if [ ! -f "$PID_FILE" ]; then
    echo "    未找到 PID 文件，尝试按固定端口停止..."
    PORT="${GITLAB_SOCKS_PORT:-1088}"
    PORT_PID=$(find_pid_by_port "$PORT")
    if [ -n "$PORT_PID" ] && ps -p "$PORT_PID" > /dev/null 2>&1; then
        echo "    - 发现监听端口的进程 (PID: $PORT_PID)。尝试终止..."
        kill "$PORT_PID" 2>/dev/null || true
        sleep 1
        if ps -p "$PORT_PID" > /dev/null 2>&1; then
            echo "    - 优雅终止失败，尝试强制终止..."
            kill -9 "$PORT_PID" 2>/dev/null || true
            sleep 1
        fi
        if ps -p "$PORT_PID" > /dev/null 2>&1; then
            echo "    错误: 无法终止进程 (PID: $PORT_PID)。请手动检查。"
        else
            echo "    代理进程已成功终止。"
        fi
    else
        echo "    未在端口 $PORT 上发现监听进程。"
    fi
else
    PID=$(awk '{print $1}' "$PID_FILE")
    PORT=$(awk '{print $2}' "$PID_FILE")
    if [ -n "$PID" ] && ps -p "$PID" > /dev/null 2>&1; then
        echo "    - 正在尝试停止代理进程 (PID: $PID, 端口: ${PORT:-unknown})..."
        kill "$PID" 2>/dev/null || true
        sleep 1
        if ps -p "$PID" > /dev/null 2>&1; then
            echo "    - 优雅终止失败，尝试强制终止..."
            kill -9 "$PID" 2>/dev/null || true
            sleep 1
        fi
        if ps -p "$PID" > /dev/null 2>&1; then
            echo "    错误: 无法终止进程 (PID: $PID)。请手动检查。"
        else
            echo "    代理进程已成功终止。"
        fi
    else
        echo "    PID 无效或进程不存在。尝试通过端口查找..."
        if [ -n "$PORT" ]; then
            PORT_PID=$(find_pid_by_port "$PORT")
            if [ -n "$PORT_PID" ] && ps -p "$PORT_PID" > /dev/null 2>&1; then
                echo "    - 发现监听端口的进程 (PID: $PORT_PID)。尝试终止..."
                kill "$PORT_PID" 2>/dev/null || true
                sleep 1
                if ps -p "$PORT_PID" > /dev/null 2>&1; then
                    echo "    - 优雅终止失败，尝试强制终止..."
                    kill -9 "$PORT_PID" 2>/dev/null || true
                    sleep 1
                fi
                if ps -p "$PORT_PID" > /dev/null 2>&1; then
                    echo "    错误: 无法终止进程 (PID: $PORT_PID)。请手动检查。"
                else
                    echo "    代理进程已成功终止。"
                fi
            else
                echo "    未在端口 $PORT 上发现监听进程。"
            fi
        else
            echo "    PID 文件未包含端口信息，无法回查。"
        fi
    fi

    # 清理 PID 文件
    rm -f "$PID_FILE"
    echo "    PID 文件已移除。"
fi

echo "
========================================="
echo "========================================="