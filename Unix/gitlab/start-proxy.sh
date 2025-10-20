#!/bin/bash
# ==============================================================================
# GitLab SOCKS 代理启动脚本
#
# 设计说明:
#   - 平台: macOS, Linux, WSL (Windows Subsystem for Linux)。
#   - 行为: 启动代理并生成条件代理文件（不修改全局 include.path）。
#   - 进程管理: 通过 PID 文件 (`.proxy-pid`) 管理代理进程，防止重复启动。
#   - 连接: 默认通过 `~/.ssh/config` 中的 `gitlab-proxy` 建立连接（可用环境变量 GITLAB_PROXY_SSH_TARGET 覆盖）。
#   - 端口: 固定使用 1080（可通过环境变量 GITLAB_SOCKS_PORT 覆盖），不做端口漂移。
# ==============================================================================

# --- 1. 定义核心变量 ---
PID_FILE="./.proxy-pid" # PID 文件用于存储正在运行的代理进程的进程号
BASE_PORT="${GITLAB_SOCKS_PORT:-1080}"
SOCKS_PORT="$BASE_PORT"
MAX_PORT_ATTEMPTS=0
SSH_LOG="/tmp/gitlab_proxy_log.txt"
# 可通过环境变量覆盖 SSH 目标（默认使用 ~/.ssh/config 中的 gitlab-proxy）
SSH_TARGET="${GITLAB_PROXY_SSH_TARGET:-gitlab-proxy}"
# 使用 socks5h 让远端服务器解析 DNS

# --- 1.1 端口探测工具函数 ---
port_in_use() {
    ss -ltnp | grep -E "LISTEN .*:${1}\\b" >/dev/null 2>&1
}
find_available_port() {
    local start="${1}"
    local end=$((start+20))
    for p in $(seq "$start" "$end"); do
        if ! port_in_use "$p"; then
            echo "$p"
            return 0
        fi
    done
    return 1
}

# 固定端口模式：若 1080 被占用则直接退出（不做端口漂移）
if port_in_use "$SOCKS_PORT"; then
    echo "🔴 错误: 固定端口 $SOCKS_PORT 已被占用。"
    echo "提示: 请先释放该端口，或临时以环境变量覆盖: GITLAB_SOCKS_PORT=1090 ./start-proxy.sh"
    ss -ltnp | grep -E "LISTEN .*:${SOCKS_PORT}\\b" || true
    exit 1
fi

PROXY_URL="socks5h://127.0.0.1:$SOCKS_PORT"

# --- 2. 检查代理是否已在运行 ---
echo "正在检查代理状态..."
if [ -f "$PID_FILE" ]; then
    PID=$(awk '{print $1}' "$PID_FILE")
    OLD_PORT=$(awk '{print $2}' "$PID_FILE")
    # 使用 ps 命令检查该 PID 对应的进程是否存在
    if [ -n "$PID" ] && ps -p "$PID" > /dev/null 2>&1; then
        echo "GitLab 代理已在运行 (PID: $PID, 端口: ${OLD_PORT:-unknown})。"
        exit 1
    else
        # 如果 PID 文件存在但进程已不存在，说明是残留的无效文件，将其清理
        echo "发现无效的 PID 文件，正在清理..."
        rm "$PID_FILE"
    fi
fi

# --- 3. 启动新的代理进程 ---
SUCCESS=0
PORT_OFFSET=0

while [ $PORT_OFFSET -le $MAX_PORT_ATTEMPTS ]; do
    SOCKS_PORT=$((BASE_PORT + PORT_OFFSET))
    PROXY_URL="socks5h://127.0.0.1:$SOCKS_PORT"

    if [ $PORT_OFFSET -gt 0 ]; then
        echo "尝试备用端口: $SOCKS_PORT"
    fi

    if port_in_use "$SOCKS_PORT"; then
        echo "端口 $SOCKS_PORT 已被占用（固定端口模式，不重试）。"
        ss -ltnp | grep -E "LISTEN .*:${SOCKS_PORT}\\b" || true
        exit 1
    fi

    echo "正在后台启动 GitLab SOCKS 代理 (端口: $SOCKS_PORT)..."
    : > "$SSH_LOG"
    ssh -fN -vv -D 127.0.0.1:${SOCKS_PORT} -o ControlMaster=no -o ServerAliveInterval=30 -o ServerAliveCountMax=6 -o TCPKeepAlive=yes -o ExitOnForwardFailure=yes -o StrictHostKeyChecking=accept-new -E "$SSH_LOG" "$SSH_TARGET"
    SSH_STATUS=$?

    if [ $SSH_STATUS -ne 0 ]; then
        if grep -q "Address already in use" "$SSH_LOG"; then
            echo "🔴 错误: 端口 $SOCKS_PORT 已被占用（固定端口模式）。"
            # 打印当前占用该端口的进程，帮助排查
            ss -ltnp | grep -E "LISTEN .*:${SOCKS_PORT}\\b" || true
            exit 1
        fi
        echo "🔴 错误: SSH 启动失败 (退出码: $SSH_STATUS)。"
        echo "请查看日志: $SSH_LOG"
        exit 1
    fi

    echo "正在验证代理状态..."
    for i in {1..10}; do
        if ss -ltn | grep -qE "LISTEN .*:${SOCKS_PORT}\\b"; then
            break
        fi
        sleep 1
    done

    if ! ss -ltn | grep -qE "LISTEN .*:${SOCKS_PORT}\\b"; then
        if grep -q "Address already in use" "$SSH_LOG"; then
            echo "日志提示端口 $SOCKS_PORT 被占用，固定端口模式下不重试。"
        fi
        echo "🔴 错误: 无法确认代理进程已启动（端口未监听）。"
        echo "请查看日志: $SSH_LOG"
        exit 1
    fi

    # 获取 ssh 进程 PID（尽力而为，不作为启动失败条件）
    PROXY_PID=$(pgrep -f "ssh.*DynamicForward=127.0.0.1:${SOCKS_PORT}" | head -n 1)
    if [ -z "$PROXY_PID" ]; then
        PROXY_PID=$(pgrep -f "ssh.*-D[[:space:]]*127\\.0\\.0\\.1:${SOCKS_PORT}" | head -n 1)
    fi

    SUCCESS=1
    break
done

if [ $SUCCESS -ne 1 ]; then
    echo "🔴 错误: 代理启动失败（固定端口 $SOCKS_PORT）。"
    echo "请查看日志: $SSH_LOG"
    exit 1
fi

echo "${PROXY_PID:-NA} $SOCKS_PORT" > "$PID_FILE"
echo "✅ 代理已成功启动: $PROXY_URL (进程号 PID: $PROXY_PID)"
echo "📄 日志文件: $SSH_LOG"

# --- 连通性自检（可选） ---
if command -v curl >/dev/null 2>&1; then
    if ! curl --socks5-hostname 127.0.0.1:$SOCKS_PORT --connect-timeout 5 -s -o /dev/null https://git.bgi.com/; then
        echo "🟡 警告: 端口监听正常，但通过 SOCKS 访问 git.bgi.com 失败。请检查网络或查看日志: $SSH_LOG"
    fi
else
    echo "ℹ️ 未检测到 curl，跳过连通性自检。"
fi

# --- 6. 创建条件代理配置文件 ---
GIT_PROXY_CONFIG_FILE="$HOME/.gitconfig-bgi-proxy-v3"
echo "正在创建 Git 条件代理文件: $GIT_PROXY_CONFIG_FILE"
cat > "$GIT_PROXY_CONFIG_FILE" << EOL
# 此文件由 GitLab 代理脚本自动生成，请勿手动修改
[http "https://git.bgi.com"]
    proxy = $PROXY_URL
EOL

# --- 6.1 确保在代理期间全局包含该配置（避免首次 clone 不走代理） ---
INCLUDE_PATH="$HOME/.gitconfig-bgi-proxy-v3"
if command -v git >/dev/null 2>&1; then
    if ! git config --global --get-all include.path | grep -Fxq "$INCLUDE_PATH"; then
        git config --global --add include.path "$INCLUDE_PATH" && \
        echo "已临时添加 include.path -> $INCLUDE_PATH"
    else
        echo "include.path 已存在，无需再次添加。"
    fi
else
    echo "警告: 未找到 git 命令，跳过 include.path 添加。"
fi

echo "ℹ️ 已在全局添加 include.path（stop-proxy.sh 会自动移除）。"

echo "请运行 './stop-proxy.sh' 来终止代理并移除 Git 代理配置（包括 include.path）。"