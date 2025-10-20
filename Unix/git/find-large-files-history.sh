#!/bin/bash
# find-large-files-history.sh (Git 历史大文件扫描 - Bash)

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

echo "--- 大文件审查器 ---"
echo "正在深度扫描仓库历史，这可能需要一些时间..."

# --- 1. 从 packfiles 中找到最大的对象并过滤 ---
# 使用 sort -k 3 -nr 来按第3列（大小）进行数字反向排序
# 使用 head -n 30 获取前30个，以防有些不是 blob
LARGEST_OBJECTS=$(git verify-pack -v .git/objects/pack/pack-*.idx | sort -k 3 -nr | head -n 30)

if [ -z "$LARGEST_OBJECTS" ]; then
    echo -e "\n未在仓库历史中发现任何打包的对象。"
    exit 0
fi

# --- 2. 找出 Top 10 的文件 (blob) ---
echo -e "\n[+] 仓库历史中体积最大的 Top 10 文件:"

COUNT=0
# 使用 process substitution 和 while read 循环来处理行
# 这样可以避免在子 shell 中修改变量的问题
while IFS= read -r line; do
    if [ $COUNT -ge 10 ]; then
        break
    fi

    hash=$(echo "$line" | awk '{print $1}')
    size=$(echo "$line" | awk '{print $3}')

    # 确认对象类型是 blob (文件)
    type=$(git cat-file -t "$hash" 2>/dev/null)
    if [ "$type" != "blob" ]; then
        continue
    fi

    # 查找此 blob 对应的文件路径
    # 这可能会找到多个路径（如果文件被重命名），我们只取第一个
    path_info=$(git rev-list --all --objects | grep "$hash" | head -n 1)
    if [ -n "$path_info" ]; then
        # 路径是 hash (40个字符) 和一个空格之后的所有内容
        path=$(echo "$path_info" | cut -c 42-)
    else
        path="(路径未找到)"
    fi

    # 转换为 MB
    size_mb=$(awk -v size="$size" 'BEGIN { printf "%.2f MB", size / 1024 / 1024 }')

    # 格式化输出
    printf "  - %-15s : %s\n" "$size_mb" "$path"

    COUNT=$((COUNT + 1))

done <<< "$LARGEST_OBJECTS"

echo -e "\n--- 分析完毕 ---"
