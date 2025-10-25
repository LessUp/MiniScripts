#requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Show-Usage {
@'
用法: .\ssh-manager.ps1 client <子命令> [参数]

子命令:
  client keygen [--type ed25519|rsa] [--force] [--comment <文本>]
  client add-host --alias <NAME> --host <IP/DOMAIN> --user <USER> [--port 22] [--identity-file <PATH>] [--force]
  client copy-id --host <ALIAS|user@host> [--key <PATH>]
  client connect [-c <PATH>] [-l]

说明:
- 默认密钥类型: ed25519。Windows 需已安装 OpenSSH Client（ssh/ssh-keygen/scp）。
- fzf.exe 存在时启用模糊选择；缺失时回退到简单选择。
'@
}

$HOME = [Environment]::GetFolderPath('UserProfile')
$SshDir = Join-Path $HOME '.ssh'
$ConfigPath = Join-Path $SshDir 'config'

function Require-OpenSSH {
  if (-not (Get-Command ssh -ErrorAction SilentlyContinue)) {
    throw '未检测到 ssh (OpenSSH Client)。请在 Windows 可选功能中启用 "OpenSSH Client" 或通过 winget 安装。'
  }
  if (-not (Get-Command ssh-keygen -ErrorAction SilentlyContinue)) {
    throw '未检测到 ssh-keygen。请安装 OpenSSH Client。'
  }
}

function Client-Keygen {
  param(
    [string]$Type = 'ed25519',
    [switch]$Force,
    [string]$Comment = "$(whoami)@$(hostname)"
  )
  Require-OpenSSH
  if (-not (Test-Path $SshDir -PathType Container)) { New-Item -ItemType Directory -Path $SshDir | Out-Null }
  $keyFile = if ($Type -ieq 'rsa') { Join-Path $SshDir 'id_rsa' } else { Join-Path $SshDir 'id_ed25519' }
  if ((Test-Path $keyFile) -and -not $Force) {
    Write-Host "密钥已存在: $keyFile (使用 --force 覆盖)" -ForegroundColor Yellow
    return
  }
  if (Test-Path $keyFile) { Remove-Item -Force "$keyFile*" }
  if ($Type -ieq 'rsa') {
    & ssh-keygen -t rsa -b 4096 -N '' -C $Comment -f $keyFile
  } else {
    & ssh-keygen -t ed25519 -N '' -C $Comment -f $keyFile
  }
  Write-Host "密钥生成完成: $keyFile" -ForegroundColor Green
}

function Remove-HostBlock {
  param([string]$Alias)
  if (-not (Test-Path $ConfigPath)) { return }
  $lines = Get-Content $ConfigPath -Raw -ErrorAction SilentlyContinue
  if (-not $lines) { return }
  $out = New-Object System.Text.StringBuilder
  $state = 'keep'
  foreach ($line in ($lines -split "`n")) {
    if ($line -match '^\s*Host\s+(.+)$') {
      $name = ($Matches[1] -split '\s+')[0]
      if ($name -eq $Alias) { $state = 'skip'; continue }
      else { $state = 'keep' }
    }
    if ($state -eq 'keep') { [void]$out.AppendLine($line) }
  }
  $content = $out.ToString().TrimEnd("`r","`n") + "`n"
  Set-Content -Path $ConfigPath -Value $content -NoNewline
}

function Client-AddHost {
  param(
    [Parameter(Mandatory=$true)][string]$Alias,
    [Parameter(Mandatory=$true)][string]$Host,
    [Parameter(Mandatory=$true)][string]$User,
    [int]$Port = 22,
    [string]$IdentityFile = "$SshDir/id_ed25519",
    [switch]$Force
  )
  if (-not (Test-Path $SshDir -PathType Container)) { New-Item -ItemType Directory -Path $SshDir | Out-Null }
  if (-not (Test-Path $ConfigPath)) { New-Item -ItemType File -Path $ConfigPath | Out-Null }
  $exists = Select-String -Path $ConfigPath -Pattern "^Host\s+$([regex]::Escape($Alias))($|\s)" -SimpleMatch -Quiet
  if ($exists -and -not $Force) { throw "Host $Alias 已存在（使用 --force 覆盖）" }
  if ($exists -and $Force) { Remove-HostBlock -Alias $Alias }
  Add-Content -Path $ConfigPath -Value @(
    "Host $Alias",
    "  HostName $Host",
    "  User $User",
    "  Port $Port",
    "  IdentityFile $IdentityFile",
    "  ServerAliveInterval 60",
    "  ServerAliveCountMax 3",
    ''
  )
  Write-Host "已追加 Host $Alias 到 $ConfigPath" -ForegroundColor Green
}

function Client-CopyId {
  param(
    [Parameter(Mandatory=$true)][string]$Host,
    [string]$Key = "$SshDir/id_ed25519.pub"
  )
  Require-OpenSSH
  if (-not (Test-Path $Key)) { throw "公钥不存在: $Key" }
  # 使用 scp + 远端追加，避免复杂转义
  $tmpName = "tmp_key_$(Get-Random).pub"
  & scp -q "$Key" "$Host:~/$tmpName"
  & ssh "$Host" "umask 077; mkdir -p ~/.ssh; touch ~/.ssh/authorized_keys; cat ~/$tmpName >> ~/.ssh/authorized_keys; rm ~/$tmpName; chmod 700 ~/.ssh; chmod 600 ~/.ssh/authorized_keys"
  Write-Host "已将公钥复制到远端: $Host" -ForegroundColor Green
}

function Get-HostsFromConfig {
  if (-not (Test-Path $ConfigPath)) { return @() }
  $lines = Get-Content $ConfigPath -ErrorAction SilentlyContinue
  if (-not $lines) { return @() }
  $hosts = @()
  foreach ($l in $lines) {
    if ($l -match '^\s*Host\s+(.+)$') {
      $name = ($Matches[1] -split '\s+')[0]
      if ($name -ne '*') { $hosts += $name }
    }
  }
  return $hosts
}

function Client-Connect {
  param(
    [string]$Config = $ConfigPath,
    [switch]$List
  )
  if (-not (Test-Path $Config)) { throw "配置文件未找到: $Config" }
  $hosts = Get-HostsFromConfig
  if (-not $hosts -or $hosts.Count -eq 0) { throw "在 $Config 中没有找到任何有效的主机定义" }
  if ($List) { $hosts | ForEach-Object { Write-Output $_ }; return }

  $fzf = Get-Command fzf.exe -ErrorAction SilentlyContinue
  if ($fzf) {
    $selected = ($hosts | & $fzf --height 40% --reverse --prompt "请选择要连接的主机: ").Trim()
  } else {
    Write-Host '未检测到 fzf.exe，将使用简单选择。' -ForegroundColor Yellow
    for ($i=0; $i -lt $hosts.Count; $i++) { Write-Host "[$($i+1)] $($hosts[$i])" }
    $idx = Read-Host '输入序号'
    if (-not [int]::TryParse($idx, [ref]$null) -or [int]$idx -lt 1 -or [int]$idx -gt $hosts.Count) { throw '无效的序号' }
    $selected = $hosts[[int]$idx - 1]
  }
  if ([string]::IsNullOrWhiteSpace($selected)) { throw '未选择任何主机' }
  Write-Host "正在连接: $selected" -ForegroundColor Cyan
  & ssh $selected
}

# --- 参数解析 ---
if ($args.Count -lt 1) { Show-Usage; exit 1 }
$module = $args[0]
switch -Regex ($module) {
  '^client$' {
    if ($args.Count -lt 2) { Show-Usage; exit 1 }
    $cmd = $args[1]
    $rest = $args[2..($args.Count-1)]
    switch -Regex ($cmd) {
      '^keygen$' {
        # 解析: --type, --force, --comment
        $type = 'ed25519'; $force = $false; $comment = "$(whoami)@$(hostname)"
        for ($i=0; $i -lt $rest.Count; $i++) {
          switch ($rest[$i]) {
            '--type' { $type = $rest[++$i]; break }
            '--force' { $force = $true; break }
            '--comment' { $comment = $rest[++$i]; break }
            default { throw "未知选项: $($rest[$i])" }
          }
        }
        Client-Keygen -Type $type -Force:$force -Comment $comment
      }
      '^add-host$' {
        $Alias=$null;$Host=$null;$User=$null;$Port=22;$IdentityFile=Join-Path $SshDir 'id_ed25519';$Force=$false
        for ($i=0; $i -lt $rest.Count; $i++) {
          switch ($rest[$i]) {
            '--alias' { $Alias = $rest[++$i]; break }
            '--host' { $Host = $rest[++$i]; break }
            '--user' { $User = $rest[++$i]; break }
            '--port' { $Port = [int]$rest[++$i]; break }
            '--identity-file' { $IdentityFile = $rest[++$i]; break }
            '--force' { $Force = $true; break }
            default { throw "未知选项: $($rest[$i])" }
          }
        }
        if (-not $Alias -or -not $Host -or -not $User) { throw '--alias/--host/--user 为必填项' }
        Client-AddHost -Alias $Alias -Host $Host -User $User -Port $Port -IdentityFile $IdentityFile -Force:$Force
      }
      '^copy-id$' {
        $Target=$null;$Key=Join-Path $SshDir 'id_ed25519.pub'
        for ($i=0; $i -lt $rest.Count; $i++) {
          switch ($rest[$i]) {
            '--host' { $Target = $rest[++$i]; break }
            '--key' { $Key = $rest[++$i]; break }
            default { throw "未知选项: $($rest[$i])" }
          }
        }
        if (-not $Target) { throw '--host 为必填项' }
        Client-CopyId -Host $Target -Key $Key
      }
      '^connect$' {
        $Config = $ConfigPath; $List=$false
        for ($i=0; $i -lt $rest.Count; $i++) {
          switch ($rest[$i]) {
            '-c' { $Config = $rest[++$i]; break }
            '--config' { $Config = $rest[++$i]; break }
            '-l' { $List = $true; break }
            '--list' { $List = $true; break }
            default { throw "未知选项: $($rest[$i])" }
          }
        }
        Client-Connect -Config $Config -List:$List
      }
      default { Show-Usage; exit 1 }
    }
  }
  default { Show-Usage; exit 1 }
}
