#!/bin/bash
# generate-diff.sh
#
# 一个用于生成 git diff 文件的 Bash 脚本。

# 当命令失败时立即退出
set -e

# --- 用户可配置参数 ---
# 注意：路径中不能包含空格。
# 指定要包含的目录或文件 (用空格分隔, 例如: "src lib")。留空则包含所有。
INCLUDE_PATHS=""
# 指定要排除的目录或文件 (用空格分隔, 例如: "*.md" "dist/")。留空则不排除任何。
EXCLUDE_PATHS=""
# --- 配置结束 ---

# --- 函数定义 ---

# 检查当前是否在 git 仓库中
function check_git_repo() {
    if ! git rev-parse --is-inside-work-tree > /dev/null 2>&1; then
        echo "错误：当前目录不是一个 git 仓库。请在您的 git 项目目录中运行此脚本。"
        exit 1
    fi
}

# 获取项目根目录并创建 diff 输出目录
function get_output_directory() {
    # 使用 git 命令获取项目根目录
    local project_root
    project_root=$(git rev-parse --show-toplevel)
    if [ $? -ne 0 ]; then
        echo "错误：无法确定 git 项目根目录。"
        exit 1
    fi
    
    # 定义并创建输出目录
    local output_dir="$project_root/_output/diffs"
    if [ ! -d "$output_dir" ]; then
        mkdir -p "$output_dir"
        echo "已创建输出目录: $output_dir"
    fi
    # 将结果返回给调用者
    echo "$output_dir"
}


# --- 主逻辑 ---

check_git_repo

# 获取统一的输出目录
DIFFS_DIR=$(get_output_directory)

# 显示菜单
echo ""
echo "请选择要生成的 diff 类型:"
echo "  a. 工作区中未提交的更改 (git diff HEAD)"
echo "  b. 从指定 commit 到 HEAD 的更改"
echo "  c. 两个指定 commit 之间的更改"
echo "  d. 从指定 commit 到当前工作区 (包含未提交的更改)"
read -p "请输入选项 (a/b/c/d): " choice

# 基础命令已优化
GIT_DIFF_CMD="git diff --unified=10 -w --no-prefix"
OUTPUT_FILE=""
GIT_FULL_CMD=""

# 构造路径过滤参数
# 注意: 这种方式不支持带空格的路径
PATHSPEC=""
if [ -n "$INCLUDE_PATHS" ]; then
    PATHSPEC=" -- $INCLUDE_PATHS"
fi
if [ -n "$EXCLUDE_PATHS" ]; then
    if [ -z "$INCLUDE_PATHS" ]; then
        PATHSPEC=" --"
    fi
    for p in $EXCLUDE_PATHS; do
        # 注意这里的单引号，它们是 git pathspec 语法的一部分
        PATHSPEC="$PATHSPEC ':(exclude)$p'"
    done
fi

case $choice in
    a)
        OUTPUT_FILE="$DIFFS_DIR/diff_workspace_uncommitted.diff"
        GIT_FULL_CMD="$GIT_DIFF_CMD HEAD"
        ;;
    b)
        read -p "请输入起始 commit hash: " startHash
        if [ -z "$startHash" ]; then echo "错误: Hash 不能为空。"; exit 1; fi
        OUTPUT_FILE="$DIFFS_DIR/diff_$(git rev-parse --short $startHash)_to_HEAD.diff"
        GIT_FULL_CMD="$GIT_DIFF_CMD ${startHash}..HEAD"
        ;;
    c)
        read -p "请输入起始 commit hash: " startHash
        read -p "请输入结束 commit hash: " endHash
        if [ -z "$startHash" ] || [ -z "$endHash" ]; then echo "错误: Hash 不能为空。"; exit 1; fi
        OUTPUT_FILE="$DIFFS_DIR/diff_$(git rev-parse --short $startHash)_$(git rev-parse --short $endHash).diff"
        GIT_FULL_CMD="$GIT_DIFF_CMD ${startHash}..${endHash}"
        ;;
    d)
        read -p "请输入起始 commit hash: " startHash
        if [ -z "$startHash" ]; then echo "错误: Hash 不能为空。"; exit 1; fi
        OUTPUT_FILE="$DIFFS_DIR/diff_$(git rev-parse --short $startHash)_to_workspace.diff"
        GIT_FULL_CMD="$GIT_DIFF_CMD $startHash"
        ;;
    *)
        echo "错误: 无效的选项 '$choice'。"
        exit 1
        ;;
}

# 将路径过滤器追加到最终命令
# 使用 eval 是因为路径过滤器中的 ':(exclude)path' 语法需要 shell 来解释
GIT_FULL_CMD="$GIT_FULL_CMD$PATHSPEC"

# 执行生成
echo "正在执行 git 命令: $GIT_FULL_CMD"
eval "$GIT_FULL_CMD" > "$OUTPUT_FILE"

# 检查命令执行结果
if [ $? -eq 0 ]; then
    # 检查文件是否有内容
    if [ -s "$OUTPUT_FILE" ]; then
        echo "成功创建 diff 文件: $OUTPUT_FILE"
    else
        echo "操作成功，但未检测到差异，已生成空文件: $OUTPUT_FILE"
    fi
else
    # 如果 git 命令失败，给出提示并删除可能已创建的空文件
    echo "生成 diff 文件失败。请检查输入的 commit hash 是否正确。"
    rm -f "$OUTPUT_FILE"
fi