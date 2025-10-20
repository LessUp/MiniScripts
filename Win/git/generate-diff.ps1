# generate-diff.ps1
#
# 一个用于生成 git diff 文件的 PowerShell 脚本。

<#!
.SYNOPSIS
    一个强大且灵活的 git diff 生成工具。

.DESCRIPTION
    此脚本提供一个菜单，让用户选择多种场景生成 diff 文件。
    核心优势:
    - 命令优化: 使用 '-w --no-prefix' 参数，忽略空白差异，输出更简洁。
    - 路径过滤: 可在脚本顶部配置包含或排除的路径，精确控制 diff 范围。
    - AI 友好: 生成的 diff 文件包含10行上下文，非常适合代码审查。
    - 目录优化: 所有 diff 文件将统一生成在项目根目录的 `_output/diffs` 文件夹下，保持源码区整洁。

.EXAMPLE
    # 运行脚本并根据菜单操作
    .\generate-diff.ps1
#!>

# --- 用户可配置参数 ---
# 指定要包含的目录或文件 (用空格分隔, 例如: "src lib"). 留空则包含所有。
$IncludePaths = ""
# 指定要排除的目录或文件 (用空格分隔, 例如: "*.md" "dist/"). 留空则不排除任何。
$ExcludePaths = ""
# --- 配置结束 ---

# --- 函数定义 ---

# 检查当前是否在 git 仓库中
function Test-IsGitRepo {
    git rev-parse --is-inside-work-tree | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Error "错误：当前目录不是一个 git 仓库。请在您的 git 项目目录中运行此脚本。"
        return $false
    }
    return $true
}

# 获取项目根目录并创建 diff 输出目录
function Get-OutputDirectory {
    # 使用 git 命令获取项目根目录
    $projectRoot = git rev-parse --show-toplevel | Out-String -Stream
    if ($LASTEXITCODE -ne 0) {
        Write-Error "错误：无法确定 git 项目根目录。"
        return $null
    }
    
    # 定义并创建输出目录
    $outputDir = Join-Path -Path $projectRoot -ChildPath "_output\diffs"
    if (-not (Test-Path -Path $outputDir)) {
        New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
        Write-Host "已创建输出目录: $outputDir"
    }
    return $outputDir
}

# 执行 git diff 并创建文件
function New-DiffFile {
    param(
        [string]$GitCommand,
        [string]$OutputFile
    )
    Write-Host "正在执行 git 命令: $GitCommand"
    Invoke-Expression $GitCommand > $OutputFile
    if ($LASTEXITCODE -eq 0) {
        if ((Get-Item $OutputFile).Length -eq 0) {
            Write-Host "操作成功，但未检测到差异，已生成空文件: $OutputFile" -ForegroundColor Yellow
        } else {
            Write-Host "成功创建 diff 文件: $OutputFile" -ForegroundColor Green
        }
    } else {
        Write-Warning "生成 diff 文件失败。请检查输入是否正确。"
        if (Test-Path $OutputFile) {
            Remove-Item $OutputFile -ErrorAction SilentlyContinue
        }
    }
}

# --- 主逻辑 ---

try {
    if (-not (Test-IsGitRepo)) { exit }

    $diffsDir = Get-OutputDirectory
    if (-not $diffsDir) { exit } # 如果无法获取输出目录，则退出

    # 显示菜单
    Write-Host "`n请选择要生成的 diff 类型:" -ForegroundColor Yellow
    Write-Host "  a. 工作区中未提交的更改 (git diff HEAD)"
    Write-Host "  b. 从指定 commit 到 HEAD 的更改"
    Write-Host "  c. 两个指定 commit 之间的更改"
    Write-Host "  d. 从指定 commit 到当前工作区 (包含未提交的更改)"
    $choice = Read-Host -Prompt "请输入选项 (a/b/c/d)"

    # 基础命令已优化
    $gitDiffBaseCmd = "git diff --unified=10 -w --no-prefix"
    $outputFile = ""
    $gitFullCmd = ""

    # 构造路径过滤参数
    $pathspec = ""
    if (-not [string]::IsNullOrWhiteSpace($IncludePaths)) {
        $pathspec += " -- " + ($IncludePaths -split ' ' | ForEach-Object { "'$_'" }) -join ' '
    }
    if (-not [string]::IsNullOrWhiteSpace($ExcludePaths)) {
        if ([string]::IsNullOrWhiteSpace($IncludePaths)) { $pathspec += " --" }
        $pathspec += " " + ($ExcludePaths -split ' ' | ForEach-Object { "':(exclude)$_'" }) -join ' '
    }

    switch ($choice.ToLower()) {
        'a' {
            $outputFile = Join-Path -Path $diffsDir -ChildPath "diff_workspace_uncommitted.diff"
            $gitFullCmd = "$gitDiffBaseCmd HEAD"
        }
        'b' {
            $startHash = Read-Host -Prompt "请输入起始 commit hash"
            if ([string]::IsNullOrWhiteSpace($startHash)) { Write-Warning "Hash 不能为空。"; exit }
            $outputFile = Join-Path -Path $diffsDir -ChildPath "diff_$(($startHash).Substring(0,7))_to_HEAD.diff"
            $gitFullCmd = "$gitDiffBaseCmd ${startHash}..HEAD"
        }
        'c' {
            $startHash = Read-Host -Prompt "请输入起始 commit hash"
            $endHash = Read-Host -Prompt "请输入结束 commit hash"
            if ([string]::IsNullOrWhiteSpace($startHash) -or [string]::IsNullOrWhiteSpace($endHash)) { Write-Warning "Hash 不能为空。"; exit }
            $outputFile = Join-Path -Path $diffsDir -ChildPath "diff_$(($startHash).Substring(0,7))_$(($endHash).Substring(0,7)).diff"
            $gitFullCmd = "$gitDiffBaseCmd ${startHash}..${endHash}"
        }
        'd' {
            $startHash = Read-Host -Prompt "请输入起始 commit hash"
            if ([string]::IsNullOrWhiteSpace($startHash)) { Write-Warning "Hash 不能为空。"; exit }
            $outputFile = Join-Path -Path $diffsDir -ChildPath "diff_$(($startHash).Substring(0,7))_to_workspace.diff"
            $gitFullCmd = "$gitDiffBaseCmd $startHash"
        }
        default {
            Write-Warning "无效的选项 '$choice'。"; exit
        }
    }

    # 将路径过滤器追加到最终命令
    $gitFullCmd = $gitFullCmd + $pathspec

    # 执行生成
    New-DiffFile -GitCommand $gitFullCmd -OutputFile $outputFile
}
catch {
    Write-Error "发生未知错误。请确保 git 已安装并且在您的 PATH 环境变量中。"
}