# Script: setup-win-client-to-linux-server.ps1
# Description: Helps set up SSH key-based authentication from a Windows client to a Linux SSH server.
# To be run on the Windows SSH CLIENT.
# Version: 1.0

# --- 1. 定义 SSH 密钥路径 ---
$SshUserHome = $env:USERPROFILE
$SshPath = Join-Path -Path $SshUserHome -ChildPath ".ssh"
$PrivateKeyPath = Join-Path -Path $SshPath -ChildPath "id_rsa"
$PublicKeyPath = Join-Path -Path $SshPath -ChildPath "id_rsa.pub"

Write-Host "--- SSH 密钥检查与生成 (Windows 客户端) ---" -ForegroundColor Cyan
Write-Host "将在以下路径检查/创建 SSH 密钥:"
Write-Host "  私钥: $PrivateKeyPath"
Write-Host "  公钥: $PublicKeyPath"
Write-Host ""

# --- 2. 检查 .ssh 目录是否存在，不存在则创建 ---
if (-not (Test-Path $SshPath -PathType Container)) {
    Write-Host "'.ssh' 目录 ($SshPath) 不存在，正在创建..." -ForegroundColor Yellow
    try {
        New-Item -ItemType Directory -Path $SshPath -ErrorAction Stop | Out-Null
        Write-Host "'.ssh' 目录已创建。" -ForegroundColor Green
    }
    catch {
        Write-Host "错误：创建 '.ssh' 目录失败: $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
} else {
    Write-Host "'.ssh' 目录 ($SshPath) 已存在。" -ForegroundColor Green
}
Write-Host ""

# --- 3. 检查 SSH 密钥对是否存在 ---
$generateNewKeys = $false
if (-not (Test-Path $PrivateKeyPath) -or -not (Test-Path $PublicKeyPath)) {
    Write-Host "SSH 密钥对 (id_rsa/id_rsa.pub) 未找到。" -ForegroundColor Yellow
    $generateNewKeys = $true
} else {
    Write-Host "找到现有的 SSH 密钥对。" -ForegroundColor Green
    $choice = Read-Host "是否要覆盖现有密钥并生成新的密钥对? (y/N)"
    if ($choice -eq 'y' -or $choice -eq 'Y') {
        Write-Host "将生成新的密钥对并覆盖现有密钥。" -ForegroundColor Yellow
        $generateNewKeys = $true
    } else {
        Write-Host "将使用现有密钥。" -ForegroundColor Green
    }
}
Write-Host ""

# --- 4. 如果需要，生成新的 SSH 密钥对 ---
if ($generateNewKeys) {
    Write-Host "正在生成新的 SSH 密钥对 (RSA 4096位)..." -ForegroundColor Yellow
    if (Test-Path $PrivateKeyPath) { Remove-Item $PrivateKeyPath -Force }
    if (Test-Path $PublicKeyPath) { Remove-Item $PublicKeyPath -Force }
    try {
        ssh-keygen -t rsa -b 4096 -f $PrivateKeyPath -N "" -C "$env:USERNAME@$env:COMPUTERNAME" -q
        if (Test-Path $PrivateKeyPath -And (Test-Path $PublicKeyPath)) {
            Write-Host "新的 SSH 密钥对已成功生成。" -ForegroundColor Green
        } else {
            Write-Host "错误：ssh-keygen 执行后未找到密钥文件。" -ForegroundColor Red; exit 1
        }
    }
    catch {
        Write-Host "错误：生成 SSH 密钥对失败: $($_.Exception.Message)" -ForegroundColor Red; exit 1
    }
}
Write-Host ""

# --- 5. 获取公钥内容 ---
if (-not (Test-Path $PublicKeyPath)) {
    Write-Host "错误：公钥文件 '$PublicKeyPath' 未找到。无法继续。" -ForegroundColor Red
    exit 1
}
$PublicKeyContent = Get-Content $PublicKeyPath -Raw
Write-Host "--- 公钥内容 ---" -ForegroundColor Cyan
Write-Host $PublicKeyContent -ForegroundColor White
Write-Host ""

# --- 6. 连接到 Linux 服务器并配置 ---
Write-Host "--- 连接到 Linux 服务器并配置 ---" -ForegroundColor Cyan
$LinuxUser = Read-Host -Prompt "请输入您在 Linux 服务器上的用户名"
$LinuxHost = Read-Host -Prompt "请输入 Linux 服务器的 IP 地址或主机名"

if ([string]::IsNullOrWhiteSpace($LinuxUser) -or [string]::IsNullOrWhiteSpace($LinuxHost)) {
    Write-Host "错误：Linux 用户名和主机名不能为空。" -ForegroundColor Red
    exit 1
}

Write-Host "正在尝试将公钥复制到 $LinuxUser@${LinuxHost}:~/.ssh/authorized_keys" -ForegroundColor Yellow
Write-Host "您可能需要输入 '$LinuxUser' 在 '$LinuxHost' 上的密码。" -ForegroundColor Yellow

# 构建在 Linux 服务器上执行的命令
# 注意 PowerShell 中对引号和变量替换的处理
$RemoteCommand = "umask 077; mkdir -p ~/.ssh; echo ""$PublicKeyContent"" >> ~/.ssh/authorized_keys; chmod 700 ~/.ssh; chmod 600 ~/.ssh/authorized_keys"

try {
    # 使用 ssh 执行远程命令。确保 ssh.exe 在 PATH 中。
    # PowerShell 的 Invoke-Command 不适用于非 PowerShell 远程主机。
    # 我们将命令通过管道传递给 ssh。
    Write-Host "将执行以下远程命令 (需要输入密码):" -ForegroundColor Magenta
    Write-Host "ssh $LinuxUser@$LinuxHost ""$RemoteCommand""" -ForegroundColor Magenta
    
    # 提供手动操作指引，因为直接通过 ssh 执行复杂命令有时会遇到转义问题
    Write-Host ""
    Write-Host "如果上述自动尝试失败，或者您希望手动操作：" -ForegroundColor Yellow
    Write-Host "1. 复制上面的公钥内容 (从 'ssh-rsa' 开始)。"
    Write-Host "2. 通过 SSH 登录到您的 Linux 服务器: ssh $LinuxUser@$LinuxHost"
    Write-Host "3. 登录后，在 Linux 服务器上执行以下命令:"
    Write-Host "   mkdir -p ~/.ssh" -ForegroundColor Green
    Write-Host "   echo '在此粘贴您复制的公钥内容' >> ~/.ssh/authorized_keys" -ForegroundColor Green
    Write-Host "   chmod 700 ~/.ssh" -ForegroundColor Green
    Write-Host "   chmod 600 ~/.ssh/authorized_keys" -ForegroundColor Green
    Write-Host "   exit" -ForegroundColor Green
    Write-Host ""
    Write-Host "请按 Enter 键尝试自动复制公钥 (可能需要输入密码)，或按 Ctrl+C 中断并手动操作。" -ForegroundColor Yellow
    Read-Host

    # 尝试自动复制
    # 注意：直接通过 ssh 执行 echo 和重定向可能因 shell 特殊字符和引号处理而出错。
    # 更可靠的方法是使用 here-string 或将命令分解。
    # 为了简化，这里提供一个基础尝试，并强烈建议用户注意手动步骤。
    
    # PowerShell 调用 ssh 时，命令字符串内的双引号需要小心处理。
    # 使用单引号包围远程命令，内部的变量 $PublicKeyContent 已经包含了公钥字符串。
    # ssh user@host 'bash commands here'
    
    $EscapedPublicKeyContent = $PublicKeyContent.Replace("'", "'\\''") # 基本转义以防公钥内容中有单引号
    $SshCommand = "umask 077; mkdir -p ~/.ssh; echo '$EscapedPublicKeyContent' >> ~/.ssh/authorized_keys; chmod 700 ~/.ssh; chmod 600 ~/.ssh/authorized_keys"

    # Execute the command
    ssh "$LinuxUser@$LinuxHost" $SshCommand

    # 无法直接从 ssh 命令的输出判断是否成功，因为 ssh 本身不返回结构化状态。
    # 最好是让用户测试。
    Write-Host ""
    Write-Host "公钥复制尝试已执行。" -ForegroundColor Green
    Write-Host "请尝试通过 SSH 免密登录到 Linux 服务器：" -ForegroundColor Green
    Write-Host "ssh $LinuxUser@$LinuxHost" -ForegroundColor Magenta
    Write-Host "如果仍然提示输入密码，请仔细检查手动操作步骤或服务器上的 SSHD 配置 (通常是 /etc/ssh/sshd_config，确保 PubkeyAuthentication yes)。" -ForegroundColor Yellow

}
catch {
    Write-Host "错误：尝试通过 SSH 连接或执行命令失败: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "请检查您的 SSH客户端、网络连接，或尝试上述手动步骤。" -ForegroundColor Yellow
}
Write-Host ""

if ($Host.Name -eq "ConsoleHost") {
    Read-Host "按 Enter 键退出"
}
