# get-repo-summary.ps1 (Windows - PowerShell)
<#!
.SYNOPSIS
    提供一个 Git 仓库的快速摘要信息。

.DESCRIPTION
    此脚本用于快速分析任何 Git 项目的概况。它会显示项目的贡献者统计、
    近期的提交活跃度、以及关键的仓库指标，帮助用户快速了解项目状态。

.EXAMPLE
    .\get-repo-summary.ps1
    # 在当前 Git 仓库根目录运行，将输出一份详细的摘要报告。
#!>

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

    # --- 1. 基本信息 ---
    $repoName = (Get-Item -Path .).Name
    Write-Host "--- Git 仓库摘要: $repoName ---" -ForegroundColor Yellow

    # --- 2. 贡献者统计 ---
    Write-Host "`n[+] 贡献者统计 (按提交次数排序):" -ForegroundColor Cyan
    git shortlog -sn --no-merges | ForEach-Object {
        $line = $_.Trim()
        $parts = $line -split "`t"
        $count = $parts[0]
        $name = $parts[1]
        Write-Host ("  - {0,-25} : {1} 提交" -f $name, $count)
    }

    # --- 3. 总体统计 ---
    Write-Host "`n[+] 关键指标:" -ForegroundColor Cyan
    $totalCommits = git rev-list --all --count
    $totalBranches = (git branch | Measure-Object -Line).Lines
    $latestTag = try { git describe --tags --abbrev=0 } catch { "无" }
    Write-Host "  - 总提交数  : $totalCommits"
    Write-Host "  - 本地分支数: $totalBranches"
    Write-Host "  - 最新标签  : $latestTag"

    # --- 4. 提交活跃度 (最近12周) ---
    Write-Host "`n[+] 提交活跃度 (最近12周):" -ForegroundColor Cyan
    $endDate = Get-Date
    $startDate = $endDate.AddDays(-84) # 12 weeks
    
    # 创建一个哈希表来存储每周的提交计数
    $weeklyCommits = [ordered]@{}
    for ($i = 0; $i -lt 12; $i++) {
        $weekStartDate = $startDate.AddDays($i * 7)
        # 将key设置为周一
        $dayOfWeek = [int]$weekStartDate.DayOfWeek
        $offset = if($dayOfWeek -eq 0) { -6 } else { 1 - $dayOfWeek }
        $monday = $weekStartDate.AddDays($offset)
        $weekKey = $monday.ToString("yyyy-MM-dd")
        if (-not $weeklyCommits.Contains($weekKey)) {
             $weeklyCommits[$weekKey] = 0
        }
    }

    # 获取最近12周的提交
    $commits = git log --since="12 weeks ago" --pretty=format:'%ci'
    foreach ($commitDateStr in $commits) {
        $commitDate = [datetime]$commitDateStr
        $dayOfWeek = [int]$commitDate.DayOfWeek
        $offset = if($dayOfWeek -eq 0) { -6 } else { 1 - $dayOfWeek }
        $monday = $commitDate.AddDays($offset)
        $weekKey = $monday.ToString("yyyy-MM-dd")

        if ($weeklyCommits.Contains($weekKey)) {
            $weeklyCommits[$weekKey]++
        }
    }

    # 找到最大计数值用于缩放
    $maxCount = 0
    $weeklyCommits.Values | ForEach-Object { if ($_ -gt $maxCount) { $maxCount = $_ } }
    if ($maxCount -eq 0) { $maxCount = 1 } # 防止除以零

    # 打印图表
    $weeklyCommits.GetEnumerator() | ForEach-Object {
        $count = $_.Value
        $barLength = [math]::Round(($count / $maxCount) * 50) # 最大长度为50个字符
        $bar = "#" * $barLength
        Write-Host ("  {0} | {1,-52} ({2} 提交)" -f $_.Name, $bar, $count)
    }

    Write-Host "`n--- 摘要生成完毕 ---" -ForegroundColor Yellow

}
catch {
    Write-Error "发生未知错误。请确保 git 已安装并且在您的 PATH 环境变量中。"
}