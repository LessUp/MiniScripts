# cleanup-branches.ps1 (Windows - PowerShell)
<#
.SYNOPSIS
    清理已合并到主分支的本地 Git 分支。

.DESCRIPTION
    此脚本会自动查找已经完全合并到 main 或 master 分支的本地分支，
    并提供一个交互式菜单，让用户确认后批量删除这些无用分支，
    从而保持本地仓库的整洁。

.EXAMPLE
    .\cleanup-branches.ps1
    # 脚本会列出可删除的分支并请求确认。
#>

# --- 函数定义 ---

# 检查是否在 git 仓库中
function Test-GitRepository {
    git rev-parse --is-inside-work-tree | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "错误: 当前目录不是一个 Git 仓库。" -ForegroundColor Red
        exit 1
    }
}

# --- 主逻辑 ---

try {
    Test-GitRepository

    # --- 1. 确定主分支 (main 或 master) ---
    $mainBranch = ""
    $branches = git branch -l 'main' 'master' | ForEach-Object { $_.Trim() }
    if ($branches -contains 'main') {
        $mainBranch = 'main'
    } elseif ($branches -contains 'master') {
        $mainBranch = 'master'
    } else {
        Write-Host "错误: 未找到 'main' 或 'master' 分支。" -ForegroundColor Red
        exit 1
    }
    Write-Host "检测到主分支为: $mainBranch" -ForegroundColor Green

    # --- 2. 查找已合并的本地分支 ---
    $currentBranch = (git rev-parse --abbrev-ref HEAD).Trim()
    $mergedBranches = git branch --merged $mainBranch | ForEach-Object { $_.Trim() }

    $branchesToDelete = $mergedBranches | Where-Object { 
        $_ -ne $mainBranch -and $_ -ne $currentBranch -and $_ -ne "* $currentBranch" 
    }

    # --- 3. 显示并请求确认 ---
    if ($branchesToDelete.Length -eq 0) {
        Write-Host "`n没有检测到可以安全删除的分支。仓库很干净！" -ForegroundColor Green
        exit 0
    }

    Write-Host "`n以下分支已完全合并到 '$mainBranch'，可以安全删除:" -ForegroundColor Yellow
    $branchesToDelete | ForEach-Object { Write-Host "  - $_" }

    $confirmation = Read-Host -Prompt "`n您确定要删除这 $($branchesToDelete.Length) 个分支吗? (y/n)"

    # --- 4. 执行删除 ---
    if ($confirmation.ToLower() -eq 'y') {
        Write-Host "`n正在删除分支..." -ForegroundColor Cyan
        foreach ($branch in $branchesToDelete) {
            git branch -d $branch
        }
        Write-Host "`n清理完毕！" -ForegroundColor Green
    } else {
        Write-Host "`n操作已取消。" -ForegroundColor Yellow
    }
}
catch {
    Write-Error "发生未知错误。请确保 git 已安装并且在您的 PATH 环境变量中。"
}
