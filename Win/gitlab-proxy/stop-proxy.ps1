# ==============================================================================
# GitLab SOCKS 代理停止脚本
#
# 设计说明:
#   - 平台: Windows (PowerShell)。
#   - 行为: 安全地终止由 start-proxy.ps1 启动的后台代理进程。
#   - 职责: 仅负责停止进程和清理 PID 文件，不修改任何 Git 配置。
# ==============================================================================

# --- 1. 脚本核心变量 ---
$PidFile = Join-Path $PSScriptRoot ".proxy-pid"
${GitProxyConfigFile} = Join-Path $env:USERPROFILE ".gitconfig-bgi-proxy-v3"

# 帮助函数：尝试从 Git 条件代理配置解析端口
function Get-SocksPortFromConfig {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return $null }
    try {
        $raw = Get-Content $Path -Raw -ErrorAction Stop
        $m = [regex]::Match($raw, 'proxy\s*=\s*socks5h?://127\.0\.0\.1:(\d+)', 'IgnoreCase')
        if ($m.Success) { return [int]$m.Groups[1].Value } else { return $null }
    } catch { return $null }
}

function Find-ProcessByListeningPort {
    param([int]$Port)
    try {
        $conn = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction Stop
        if ($conn -and $conn.OwningProcess) { return Get-Process -Id $conn.OwningProcess -ErrorAction SilentlyContinue }
    } catch {
        $line = & cmd.exe /c "netstat -ano | findstr LISTENING | findstr :$Port"
        if ($line) {
            $pid = ($line -split "\s+")[-1]
            return Get-Process -Id $pid -ErrorAction SilentlyContinue
        }
    }
    return $null
}

# --- 2. 脚本主逻辑 ---
Clear-Host
Write-Host "========================================="
Write-Host "==  GitLab SOCKS 代理停止器 (v3.4)     =="
Write-Host "========================================="
Write-Host ""

# 步骤 1: 检查并停止代理进程
Write-Host " [*] 步骤 1: 正在查找并停止代理进程..."
if (-not (Test-Path $PidFile)) {
    Write-Host "     未找到 PID 文件，尝试通过端口扫描定位代理进程..." -ForegroundColor Yellow
    $socksPort = Get-SocksPortFromConfig -Path ${GitProxyConfigFile}
    if ($socksPort) {
        $p = Find-ProcessByListeningPort -Port $socksPort
        if ($p) {
            Write-Host "     发现监听端口 $socksPort 的进程 (PID: $($p.Id)，Name: $($p.ProcessName))，正在终止..." -ForegroundColor Yellow
            Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 1
            if (Get-Process -Id $p.Id -ErrorAction SilentlyContinue) {
                Write-Host "     错误: 无法终止进程 (PID: $($p.Id))。" -ForegroundColor Red
                Write-Host "        排查: 以管理员身份运行此脚本，或执行: taskkill /PID $($p.Id) /F" -ForegroundColor Gray
            } else {
                Write-Host "     已终止进程，继续清理。" -ForegroundColor Green
            }
        } else {
            Write-Host "     未定位到监听端口 $socksPort 的进程。" -ForegroundColor Yellow
            Write-Host "        排查建议: netstat -ano | findstr LISTENING | findstr :$socksPort" -ForegroundColor Gray
        }
    } else {
        Write-Host "     无法从 ${GitProxyConfigFile} 解析 SOCKS 端口。" -ForegroundColor Yellow
        Write-Host "        排查建议: type ${GitProxyConfigFile}" -ForegroundColor Gray
    }
} else {

    $oldPid = Get-Content $PidFile -ErrorAction SilentlyContinue
    if (-not $oldPid) {
        Write-Host "     PID 文件为空，无法定位进程。" -ForegroundColor Yellow
        Remove-Item $PidFile -Force
        Write-Host ""
        Read-Host "按回车键退出..."
        return
    }

    $process = Get-Process -Id $oldPid -ErrorAction SilentlyContinue
    if ($process) {
        Write-Host "     发现代理进程 (PID: $oldPid)，正在终止..."
        Stop-Process -Id $oldPid -Force
        # 验证进程是否已终止
        Start-Sleep -Seconds 1
        if (Get-Process -Id $oldPid -ErrorAction SilentlyContinue) {
            Write-Host "     错误: 无法终止进程 (PID: $oldPid)。请手动检查。" -ForegroundColor Red
            Write-Host "        排查: 以管理员身份运行，或执行: taskkill /PID $oldPid /F" -ForegroundColor Gray
        } else {
            Write-Host "     代理进程已成功终止。" -ForegroundColor Green
        }
    } else {
        Write-Host "     未找到 PID 为 $oldPid 的进程，可能已被手动停止。"
    }
}

# 步骤 2: 清理 PID 文件
Write-Host ""
Write-Host " [*] 步骤 2: 清理 PID 文件..."
Remove-Item $PidFile -Force
Write-Host "     PID 文件已移除。"

Write-Host ""
Write-Host " [*] 步骤 3: 删除 Git 条件代理配置文件..."
if (Test-Path ${GitProxyConfigFile}) {
    Remove-Item ${GitProxyConfigFile} -Force
    Write-Host "     已删除 ${GitProxyConfigFile}。"
} else {
    Write-Host "     未找到 ${GitProxyConfigFile}，无需删除。"
}

Write-Host ""
Write-Host " 所有清理操作已完成。"
Read-Host "按回车键退出..."
