#!/bin/bash
# generate-changelog.sh (Unix/Linux/macOS - Bash)

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

# --- 1. 获取 Git 引用范围 ---
LATEST_TAG=$(git describe --tags --abbrev=0 2>/dev/null)
if [ -z "$LATEST_TAG" ]; then
    echo "警告: 未找到任何标签。将从最初的提交开始生成日志。"
    START_REF=$(git rev-list --max-parents=0 HEAD)
else
    echo "找到最新标签: $LATEST_TAG"
    START_REF=$LATEST_TAG
fi

read -p "请输入起始引用 (默认为: $START_REF): " user_start_ref
if [ -n "$user_start_ref" ]; then
    START_REF=$user_start_ref
fi

END_REF="HEAD"
read -p "请输入结束引用 (默认为: HEAD): " user_end_ref
if [ -n "$user_end_ref" ]; then
    END_REF=$user_end_ref
fi

echo "正在生成从 '$START_REF' 到 '$END_REF' 的更新日志..."

# --- 2. 定义提交类型和标题 ---
# 使用关联数组 (需要 Bash 4+)
declare -A COMMIT_TYPES
COMMIT_TYPES=( \
    ["feat"]='✨ 新功能 (Features)' \
    ["fix"]='🐛 Bug 修复 (Bug Fixes)' \
    ["perf"]='⚡ 性能优化 (Performance Improvements)' \
    ["refactor"]='♻️ 代码重构 (Code Refactoring)' \
    ["docs"]='📚 文档更新 (Documentation)' \
    ["style"]='💎 代码风格 (Styles)' \
    ["test"]='✅ 测试相关 (Tests)' \
    ["build"]='📦 构建系统 (Builds)' \
    ["ci"]='🔁 持续集成 (Continuous Integration)' \
    ["chore"]='🔧 其他杂项 (Chores)' \
)

# --- 3. 获取并分类提交 ---
# 创建临时目录存放分类后的提交
TMP_DIR=$(mktemp -d)
trap 'rm -rf -- "$TMP_DIR"' EXIT

# 读取 git log 并分类
git log --pretty=format:'%s' "${START_REF}..${END_REF}" --no-merges | while IFS= read -r commit; do
    # 正则匹配: type(scope): subject
    if [[ $commit =~ ^([a-z]+)(\\(.+\\))?(!)?:[[:space:]](.+) ]]; then
        type="${BASH_REMATCH[1]}"
        scope="${BASH_REMATCH[3]}"
        subject="${BASH_REMATCH[5]}"

        if [[ -v COMMIT_TYPES["$type"] ]]; then
            if [ -n "$scope" ]; then
                echo "- **$scope**: $subject" >> "$TMP_DIR/$type.tmp"
            else
                echo "- $subject" >> "$TMP_DIR/$type.tmp"
            fi
        fi
    fi
done

# --- 4. 生成 Markdown 内容 ---
OUTPUT_FILE="CHANGELOG_new.md"
NEW_VERSION=$(git describe --tags $END_REF 2>/dev/null | sed 's/^v//')
[ -z "$NEW_VERSION" ] && NEW_VERSION="Unreleased"

{ 
    echo "# Changelog - $NEW_VERSION ($(date +%Y-%m-%d))"
    echo ""
} > "$OUTPUT_FILE"

HAS_CONTENT=false
# 按预定顺序输出
for type in feat fix perf refactor docs style test build ci chore; do
    tmp_file="$TMP_DIR/$type.tmp"
    if [ -f "$tmp_file" ]; then
        HAS_CONTENT=true
        echo "### ${COMMIT_TYPES[$type]}" >> "$OUTPUT_FILE"
        echo "" >> "$OUTPUT_FILE"
        cat "$tmp_file" >> "$OUTPUT_FILE"
        echo "" >> "$OUTPUT_FILE"
    fi
done

if [ "$HAS_CONTENT" = false ]; then
    echo -e "\n在指定范围内没有找到符合约定式提交规范的记录。"
    rm -f "$OUTPUT_FILE"
    exit 0
fi

# --- 5. 完成 ---
echo -e "\n成功生成更新日志: $OUTPUT_FILE"
