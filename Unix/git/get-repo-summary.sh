#!/bin/bash
# get-repo-summary.sh (Unix/Linux/macOS - Bash)

# --- 函数定义 ---

# 检查是否在 git 仓库中
check_git_repo() {
    if ! git rev-parse --is-inside-work-tree > /dev/null 2>&1; then
        echo "错误: 当前目录不是一个 Git 仓库。"
        exit 1
    fi
}

# --- 主逻辑 ---

check_git_repo

# --- 1. 基本信息 ---
REPO_NAME=$(basename "$PWD")
echo "--- Git 仓库摘要: $REPO_NAME ---"

# --- 2. 贡献者统计 ---
echo -e "\n[+] 贡献者统计 (按提交次数排序):"
git shortlog -sn --no-merges | awk '{
    count = $1;
    $1 = "";
    name = substr($0, 2);
    printf "  - %-25s : %s 提交\n", name, count;
}'

# --- 3. 总体统计 ---
echo -e "\n[+] 关键指标:"
TOTAL_COMMITS=$(git rev-list --all --count)
TOTAL_BRANCHES=$(git branch | wc -l | xargs)
LATEST_TAG=$(git describe --tags --abbrev=0 2>/dev/null || echo "无")
echo "  - 总提交数  : $TOTAL_COMMITS"
echo "  - 本地分支数: $TOTAL_BRANCHES"
echo "  - 最新标签  : $LATEST_TAG"

# --- 4. 提交活跃度 (最近12周) ---
echo -e "\n[+] 提交活跃度 (最近12周):"

# 兼容 macOS, 优先使用 gdate
if command -v gdate &> /dev/null; then
    DATE_CMD="gdate"
elif date --version &>/dev/null; then # GNU date
    DATE_CMD="date"
else # BSD date on macOS
    echo "  警告: 检测到 macOS 原生 date, 活跃度统计可能不准。建议安装 'coreutils' (brew install coreutils) 以使用 gdate。"
    DATE_CMD="date"
fi

# 使用关联数组 (需要 Bash 4+)
declare -A weekly_commits

# 初始化最近12周的键 (从本周的周一开始)
for i in {11..0}; do
    # 获取i周前的周一
    if [[ "$DATE_CMD" == "gdate" ]] || [[ "$DATE_CMD" == "date" && "$(date --version)" == *"GNU"* ]]; then
        week_key=$($DATE_CMD -d "-$i weeks monday" +%Y-%m-%d)
    else # BSD date
        week_key=$(TZ=UTC $DATE_CMD -v-${i}w -v-mon +%Y-%m-%d)
    fi
    weekly_commits["$week_key"]=0
done

# 获取最近12周的提交时间戳
git log --since="12 weeks ago" --pretty=format:'%ct' | while read commit_ts; do
    if [[ "$DATE_CMD" == "gdate" ]] || [[ "$DATE_CMD" == "date" && "$(date --version)" == *"GNU"* ]]; then
        commit_monday=$($DATE_CMD -d "@$commit_ts -$(($($DATE_CMD -d "@$commit_ts" +%u) - 1)) days" +%Y-%m-%d)
    else # BSD date
        commit_monday=$(TZ=UTC $DATE_CMD -r $commit_ts -v-mon +%Y-%m-%d)
    fi
    
    if [[ -v weekly_commits["$commit_monday"] ]]; then
        ((weekly_commits["$commit_monday"]++))
    fi

done

# 找到最大计数值用于缩放
max_count=0
for count in "${weekly_commits[@]}"; do
    if (( count > max_count )); then
        max_count=$count
    fi
done
[[ $max_count -eq 0 ]] && max_count=1 # 防止除以零

# 排序并打印图表
sorted_keys=($(for key in "${!weekly_commits[@]}"; do echo "$key"; done | sort))
for key in "${sorted_keys[@]}"; do
    count=${weekly_commits[$key]}
    # bash doesn't do floating point, so multiply first
    bar_length=$(( (count * 50) / max_count ))
    bar=$(printf '#%.0s' $(seq 1 $bar_length) 2>/dev/null)
    printf "  %s | %-52s (%s 提交)\n" "$key" "$bar" "$count"
done

echo -e "\n--- 摘要生成完毕 ---"