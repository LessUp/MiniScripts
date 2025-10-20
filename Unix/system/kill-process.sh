#!/bin/bash
# kill-process.sh
#
# 一个高级的进程终止脚本，支持按名称、PID 或端口查找，并提供交互式选择。

# --- 配置 ---
set -e
set -o pipefail

# --- 默认值 ---
SEARCH_TERM=""
SEARCH_BY=""
SIGNAL="TERM"
FORCE_KILL=false
INTERACTIVE=true
DRY_RUN=false

# --- 颜色定义 ---
C_RESET='\033[0m'
C_RED='\033[0;31m'
C_YELLOW='\033[0;33m'
C_CYAN='\033[0;36m'
C_BOLD='\033[1m'

# --- 函数定义 ---

function show_usage() {
    echo "用法: $0 --name <模式> | --pid <PID> | --port <端口> [选项]"
    echo "查找并终止进程。"
    echo
    echo "查找方式 (必须提供一个):"
    echo "  --name <模式>           按进程名或命令行模式查找。"
    echo "  --pid <PID>             按进程 ID 查找。"
    echo "  --port <端口>           按监听的 TCP 端口查找 (需要 lsof)。"
    echo
    echo "选项:"
    echo "  -s, --signal <信号>     要发送的信号 (例如 TERM, KILL, HUP, 9, 15)。默认为 TERM。"
    echo "  -f, --force             强制使用 SIGKILL 信号 (等同于 --signal KILL)。"
    echo "  -y, --yes               自动确认，跳过所有交互式提示。"
    echo "      --dry-run           演练模式，只显示将要执行的操作。"
    echo "  -h, --help              显示此帮助信息。"
}

# --- 参数解析 ---
while [[ $# -gt 0 ]]; do
    case $1 in
        --name) SEARCH_BY="name"; SEARCH_TERM="$2"; shift 2;;
        --pid) SEARCH_BY="pid"; SEARCH_TERM="$2"; shift 2;;
        --port) SEARCH_BY="port"; SEARCH_TERM="$2"; shift 2;;
        -s|--signal) SIGNAL="$2"; shift 2;;
        -f|--force) FORCE_KILL=true; shift;;
        -y|--yes) INTERACTIVE=false; shift;;
        --dry-run) DRY_RUN=true; shift;;
        -h|--help) show_usage; exit 0;; 
        -*) echo "错误: 未知选项: $1" >&2; show_usage; exit 1;; 
    esac
done

# --- 主逻辑 ---

# 1. 验证输入
if [ -z "$SEARCH_BY" ]; then echo "错误: 必须提供一种查找方式。" >&2; show_usage; exit 1; fi
if [ "$FORCE_KILL" = true ]; then SIGNAL="KILL"; fi

# 2. 查找进程
printf "${C_CYAN}正在按 %s '%s' 查找进程...${C_RESET}\n" "$SEARCH_BY" "$SEARCH_TERM"
PIDS=()
case $SEARCH_BY in
    name) pids_found=$(pgrep -af "$SEARCH_TERM" | awk '{print $1}') ;; 
    pid) pids_found=$SEARCH_TERM ;; 
    port) 
        if ! command -v lsof &> /dev/null; then echo "错误: 'lsof' 命令未找到，无法按端口查找。" >&2; exit 1; fi
        pids_found=$(lsof -iTCP:"$SEARCH_TERM" -sTCP:LISTEN -t -P -n) 
        ;;
esac

if [ -z "$pids_found" ]; then echo "没有找到匹配的进程。"; exit 0; fi

# 获取进程详细信息
PROCESS_INFO=$(ps -o pid,user,ppid,stat,%cpu,%mem,etime,command -f -p "$pids_found" | sed 's/\s\s*/ /g')
mapfile -t PIDS < <(echo "$pids_found")
mapfile -t PROCESS_LINES < <(echo "$PROCESS_INFO" | tail -n +2)

printf "${C_YELLOW}找到 %d 个匹配的进程:${C_RESET}\n" "${#PIDS[@]}"
echo "$PROCESS_INFO"

# 3. 交互式选择
TARGET_PIDS=()
if [ "$INTERACTIVE" = true ] && [ ${#PIDS[@]} -gt 1 ]; then
    read -p $"请输入要终止的进程编号 (例如: 1,3 或 all，按 Enter 取消): " selection
    if [ -z "$selection" ]; then echo "操作已取消。"; exit 0; fi
    if [[ "$selection" == "all" ]]; then
        TARGET_PIDS=("${PIDS[@]}")
    else
        IFS=',' read -ra a <<< "$selection"
        for i in "${a[@]}"; do
            if [[ "$i" -ge 1 && "$i" -le ${#PIDS[@]} ]]; then
                TARGET_PIDS+=("${PIDS[$i-1]}")
            fi
        done
    fi
else
    TARGET_PIDS=("${PIDS[@]}")
fi

if [ ${#TARGET_PIDS[@]} -eq 0 ]; then echo "没有选择任何进程。"; exit 0; fi

# 4. 确认并执行
if [ "$INTERACTIVE" = true ]; then
    printf "\n将使用 ${C_BOLD}SIG%s${C_RESET} 信号终止以下 PID: ${C_YELLOW}%s${C_RESET}\n" "$SIGNAL" "${TARGET_PIDS[*]}"
    read -p "你确定吗? (y/N) " -n 1 -r; echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then echo "操作已取消。"; exit 1; fi
fi

# 5. 终止进程
for pid in "${TARGET_PIDS[@]}"; do
    if [ "$DRY_RUN" = true ]; then
        printf "[演练] 将执行: kill -s %s %s\n" "$SIGNAL" "$pid"
    else
        printf "正在终止 PID %s... " "$pid"
        if kill -s "$SIGNAL" "$pid" 2>/dev/null; then
            printf "${C_GREEN}成功。${C_RESET}\n"
        else
            printf "${C_RED}失败。${C_RESET}\n"
        fi
    fi
done

printf "\n${C_CYAN}操作完成。${C_RESET}\n"
