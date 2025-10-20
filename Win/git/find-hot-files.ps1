# find-hot-files.ps1 (Windows - PowerShell)
<#
.SYNOPSIS
    分析 Git 提交历史，找出修改最频繁的“热点”文件。

.DESCRIPTION
    此脚本会统计指定数量的最新提交中，每个文件被修改的次数。
    通过识别这些“热点”文件，可以帮助定位项目的核心模块、复杂性高的区域或潜在的设计问题。

.PARAMETER CommitLimit
    要分析的最新提交数量。默认为 500。

.EXAMPLE
    .\find-hot-files.ps1
    # 分析最近 500 次提交，并列出 Top 10 热点文件。

.EXAMPLE
    .\find-hot-files.ps1 -CommitLimit 1000
    # 分析最近 1000 次提交。
#>

param(
    [int]$CommitLimit = 500
)

# --- 函数定义 ---

# 检查是否在 git 仓库中
function Check-GitRepo {
    git rev-parse --is-inside-work-tree | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "错误: 当前目录不是一个 Git 仓库。" -ForegroundColor Red
        exit 1
    }
}

# --- 主逻辑 ---

try {
    Check-GitRepo

    Write-Host "--- 热点文件分析 (最近 $CommitLimit 次提交) ---" -ForegroundColor Yellow
    Write-Host "正在分析，请稍候..."

    # --- 1. 获取文件修改历史 ---
    $changedFiles = git log --pretty=format: --name-only -n $CommitLimit --no-merges

    # --- 2. 统计、排序并选出 Top 10 ---
    $hotFiles = $changedFiles | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Group-Object | Sort-Object -Property Count -Descending | Select-Object -First 10

    # --- 3. 显示结果 ---
    if ($null -eq $hotFiles) {
        Write-Host "`n在指定的提交范围内未找到任何文件修改记录。" -ForegroundColor Green
        exit 0
    }

    Write-Host "`n[+] 修改最频繁的 Top 10 文件:" -ForegroundColor Cyan
    $hotFiles | ForEach-Object {
        Write-Host ("  - {0,-50} : {1} 次修改" -f $_.Name, $_.Count)
    }

    Write-Host "`n--- 分析完毕 ---" -ForegroundColor Yellow

}
catch {
    Write-Error "发生未知错误。请确保 git 已安装并且在您的 PATH 环境变量中。"
}
