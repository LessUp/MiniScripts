# ==============================================================================
# GitLab SOCKS 代理启动脚本
#
# 设计说明:
#   - 平台: Windows (PowerShell)。
#   - 行为: 后台启动代理，生成 Git 条件代理文件。
#   - 依赖: 全局 SSH 配置文件 (~/.ssh/config)。
# ==============================================================================

# --- 1. 脚本核心变量 ---
$SshHostAlias = "gitlab-proxy"       # 要连接的 SSH 主机别名 (必须在 ~/.ssh/config 中定义)
$SocksPort    = 1080

$SshExecutable = "C:\Windows\System32\OpenSSH\ssh.exe"
$PidFile = Join-Path $PSScriptRoot ".proxy-pid"
$LogFile = Join-Path $env:TEMP "gitlab_proxy_log.txt"

# Git 条件代理配置
$GitProxyConfigFile = Join-Path $env:USERPROFILE ".gitconfig-bgi-proxy-v3"

# 远端主机（用于在未配置别名时的回退方案）
# 请按需修改为你的跳板机/内网主机与用户名
$SshRemoteHost = "10.227.5.229"  # 对应原 config 中 dev10 的 HostName
$SshRemoteUser = "shijiashuai"   # 你的内网账户名

# 用户 HOME 与 SSH 配置路径
$UserHome = $env:USERPROFILE
$SshConfigPath = Join-Path $UserHome ".ssh\config"

# --- Helper: 端口检测与选择 ---
function Test-PortFree([int]$Port) {
    try {
        $null = Get-NetTCPConnection -LocalPort $Port -ErrorAction Stop
        return $false
    } catch {
        $netstat = & cmd.exe /c "netstat -ano | findstr LISTENING | findstr :$Port"
        return -not [bool]$netstat
    }
}

function Find-FreePort([int]$start, [int]$count) {
    for ($p = $start; $p -lt ($start + $count); $p++) {
        if (Test-PortFree $p) { return $p }
    }
    return $null
}

# --- 2. 脚本主逻辑 ---
Clear-Host
Write-Host "========================================="
Write-Host "==  GitLab SOCKS 代理启动器 (v3.4)     =="
Write-Host "========================================="
Write-Host ""

# 步骤 1: 检查依赖
Write-Host " [*] 步骤 1: 检查依赖..."
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Host "     错误: Git 未安装或未在系统 PATH 中。" -ForegroundColor Red; Read-Host; return
}
if (-not (Test-Path $SshExecutable)) {
    $autoSsh = (Get-Command ssh -ErrorAction SilentlyContinue)
    if ($autoSsh) { $SshExecutable = $autoSsh.Source }
}
if (-not (Test-Path $SshExecutable)) {
    Write-Host "     错误: 未找到 ssh 可执行文件: $SshExecutable" -ForegroundColor Red
    Write-Host "        排查: 在 PowerShell 中执行 'Get-Command ssh'，或检查 Windows 可选功能 'OpenSSH 客户端' 是否安装。" -ForegroundColor Red
    Read-Host; return
}
Write-Host "     依赖检查通过。"

# 步骤 2: 清理旧进程
Write-Host ""
Write-Host " [*] 步骤 2: 检查并清理旧的代理进程..."
if (Test-Path $PidFile) {
    $oldPid = Get-Content $PidFile -ErrorAction SilentlyContinue
    if ($oldPid -and (Get-Process -Id $oldPid -ErrorAction SilentlyContinue)) {
        Write-Host "     发现旧的代理进程 (PID: $oldPid)，正在终止它..." -ForegroundColor Yellow
        Stop-Process -Id $oldPid -Force
    }
    Remove-Item $PidFile -Force
    Write-Host "     旧进程与 PID 文件已清理。"
} else {
    Write-Host "     未发现旧的 PID 文件。"
}

# 步骤 2.5: 选择可用 SOCKS 端口
Write-Host ""
Write-Host " [*] 步骤 2.5: 检查端口占用并选择可用端口..."
$free = Find-FreePort -start $SocksPort -count 20
if (-not $free) {
    Write-Host "     错误: 在 $SocksPort..$($SocksPort+19) 范围内未找到可用端口。" -ForegroundColor Red
    Write-Host "        排查: 运行 'netstat -ano | findstr LISTENING | findstr :$SocksPort' 查看占用进程。" -ForegroundColor Red
    Read-Host; return
}
if ($free -ne $SocksPort) {
    Write-Host "     端口 $SocksPort 被占用，改用 $free。" -ForegroundColor Yellow
    $SocksPort = $free
} else {
    Write-Host "     端口 $SocksPort 可用。"
}

# 步骤 3: 创建或更新 Git 代理配置文件
Write-Host ""
Write-Host " [*] 步骤 3: 准备 Git 条件代理配置文件..."
$gitConfigContent = @"
# 此文件由 GitLab 代理脚本自动生成和管理
[http "https://git.bgi.com"]
    proxy = socks5h://127.0.0.1:$SocksPort
"@
Set-Content -Path $GitProxyConfigFile -Value $gitConfigContent -Force
Write-Host "     Git 条件代理配置文件已准备就绪。 ($GitProxyConfigFile)"

# 步骤 4: 统一配置说明（不修改 .gitconfig）
Write-Host ""
Write-Host " [*] 步骤 4: 跳过 .gitconfig include.path 修改（已采用统一 includeIf 模板）"
Write-Host "     请确保已将 v3/gitconfig/.gitconfig 模板复制为全局 .gitconfig，并包含 includeIf 规则。"

# 步骤 5: 启动 SSH 代理进程
Write-Host ""
Write-Host " [*] 步骤 5: 正在后台启动 SSH 代理 ($SshHostAlias)..."
$aliasAvailable = $false
if (Test-Path $SshConfigPath) {
    try {
        $cfgRaw = Get-Content $SshConfigPath -Raw -ErrorAction Stop
        if ($cfgRaw -match "(?ms)^[\t ]*Host[\t ]+gitlab-proxy\b") { $aliasAvailable = $true }
    } catch { $aliasAvailable = $false }
}
if ($aliasAvailable) {
    Write-Host " [*] 步骤 5: 使用别名模式启动 SSH 代理 (Host $SshHostAlias) ..."
    $arguments = "-F `"$SshConfigPath`" -N -o BatchMode=yes -o ServerAliveInterval=30 -o ServerAliveCountMax=6 -o TCPKeepAlive=yes -o ExitOnForwardFailure=yes -o RequestTTY=no -D 127.0.0.1:$SocksPort -E `"$LogFile`" $SshHostAlias"
} else {
    Write-Host " [*] 步骤 5: 未检测到 '~/.ssh/config' 中的 Host $SshHostAlias，使用显式回退模式启动..." -ForegroundColor Yellow
    $arguments = "-N -o BatchMode=yes -o ExitOnForwardFailure=yes -o RequestTTY=no -o ServerAliveInterval=30 -o ServerAliveCountMax=6 -o TCPKeepAlive=yes -D 127.0.0.1:$SocksPort -l $SshRemoteUser -E `"$LogFile`" $SshRemoteHost"
}
$process = $null
try {
    # 使用 Start-Process 启动后台进程，-PassThru 会返回一个进程对象
    $process = Start-Process -FilePath $SshExecutable -ArgumentList $arguments -WindowStyle Hidden -PassThru -ErrorAction Stop
} catch {
    # 如果 Start-Process 失败，捕获异常并显示详细错误
    Write-Host "     错误: 启动 SSH 进程失败。" -ForegroundColor Red
    Write-Host "        错误详情: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "        请检查您的全局 '~/.ssh/config' 中的配置，并尝试手动运行以下命令排查:" -ForegroundColor Red
    Write-Host "        `"$SshExecutable`" $arguments" -ForegroundColor Gray
    Read-Host; return
}

# 步骤 6: 验证代理并保存 PID
Write-Host ""
Write-Host " [*] 步骤 6: 正在验证代理是否成功启动..."
# 最多等待 12 秒，循环检测端口监听与进程状态
$maxWait = 12
$portListening = $null
for ($i = 0; $i -lt $maxWait; $i++) {
    Start-Sleep -Seconds 1
    $proxyProcessStillRunning = Get-Process -Id $process.Id -ErrorAction SilentlyContinue
    try {
        $portListening = Get-NetTCPConnection -LocalPort $SocksPort -State Listen -ErrorAction Stop
    } catch {
        $portListening = & cmd.exe /c "netstat -ano | findstr LISTENING | findstr :$SocksPort"
    }
    if ($proxyProcessStillRunning -and $portListening) { break }
    if (-not $proxyProcessStillRunning) { break }
}

if ($proxyProcessStillRunning -and $portListening) {
    $process.Id | Out-File $PidFile
    Write-Host "     代理已成功启动: socks5h://127.0.0.1:$SocksPort (PID: $($process.Id))" -ForegroundColor Green
    Write-Host "     日志文件: $LogFile" -ForegroundColor Gray
    if (Get-Command curl.exe -ErrorAction SilentlyContinue) {
        $curlCmd = "curl.exe --socks5-hostname 127.0.0.1:$SocksPort --connect-timeout 5 -s -o NUL https://git.bgi.com/"
        try {
            $curlExit = (Start-Process -FilePath "cmd.exe" -ArgumentList "/c $curlCmd" -WindowStyle Hidden -PassThru -Wait -ErrorAction Stop).ExitCode
            if ($curlExit -ne 0) {
                Write-Host "     警告: 端口监听正常，但通过 SOCKS 访问 git.bgi.com 失败。请检查网络或查看日志: $LogFile" -ForegroundColor Yellow
            }
        } catch {
            Write-Host "     警告: 连通性自检出现异常: $($_.Exception.Message)" -ForegroundColor Yellow
        }
    } else {
        Write-Host "     未检测到 curl.exe，跳过连通性自检。" -ForegroundColor DarkYellow
    }
} else {
    Write-Host "     错误: 未能检测到代理监听进程。" -ForegroundColor Red
    if (-not $proxyProcessStillRunning) {
        Write-Host "        原因: SSH 进程启动后退出了，可能是认证失败或端口被占用（已启用 ExitOnForwardFailure）。" -ForegroundColor Yellow
    } elseif (-not $portListening) {
        Write-Host "        原因: 进程正在运行，但端口 $SocksPort 未监听，可能是配置缺少 DynamicForward；现已改为命令行强制添加 -D。" -ForegroundColor Yellow
    }
    Write-Host "        请检查 '~/.ssh/config' 中 Host $SshHostAlias 的配置或手动运行以下命令排查:" -ForegroundColor Red
    Write-Host "        `"$SshExecutable`" $arguments" -ForegroundColor Gray
    Write-Host "        排查建议：" -ForegroundColor Red
    Write-Host "          1) 查看日志: type `"$LogFile`"" -ForegroundColor Gray
    Write-Host "          2) 手动调试 SSH: `"$SshExecutable`" -vvv $arguments" -ForegroundColor Gray
    Write-Host "          3) 检查端口占用: netstat -ano | findstr LISTENING | findstr :$SocksPort" -ForegroundColor Gray
    Write-Host "          4) 测试 SOCKS 访问: curl.exe --socks5-hostname 127.0.0.1:$SocksPort https://git.bgi.com/ -v" -ForegroundColor Gray
    # 尝试终止可能仍在运行的僵尸进程
    Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
}

Write-Host ""
Read-Host "按回车键退出..."

