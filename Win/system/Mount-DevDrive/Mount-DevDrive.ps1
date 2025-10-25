# Mount-DevDrive.ps1 —— Windows To Go / Dev Drive (ReFS) 的 VHDX 自动挂载脚本（终版）
# 你的配置（如需更改，改这里）：
$vhx    = 'C:\Data\DevDrive\DevDrive.vhdx'   # VHDX 路径
$label  = 'Dev'                               # 目标卷标
$letter = 'D'                                 # 期望盘符

# 行为配置（WTG 友好，默认不改系统策略）
$bootDelaySeconds     = 30      # 开机后等待，给存储栈/USB/WTG 枚举留时间
$ensureSanOnlineAll   = $false  # ← WTG 建议保持 false；若你愿意系统级自动联机，改成 $true
$maxWaitAttachRetries = 60      # 等待磁盘已附加的重试次数
$maxWaitVolumeRetries = 60      # 等待卷枚举的重试次数
$waitIntervalMs       = 500

# ===== 日志基建 =====
$ErrorActionPreference = 'Stop'
$logDir  = 'C:\Scripts\Logs'
New-Item -ItemType Directory -Path $logDir -Force | Out-Null
$logPath = Join-Path $logDir ("Mount-DevDrive_{0:yyyyMMdd_HHmmss}.log" -f (Get-Date))

function Write-Log {
  param([string]$msg, [ValidateSet('INFO','WARN','ERROR')][string]$level='INFO')
  $line = "[{0:yyyy-MM-dd HH:mm:ss.fff}][{1}] {2}" -f (Get-Date), $level, $msg
  $line | Out-File -FilePath $logPath -Append -Encoding UTF8
  try {
    if (-not [System.Diagnostics.EventLog]::SourceExists('DevDrive-Mount')) {
      New-EventLog -LogName Application -Source 'DevDrive-Mount' | Out-Null
    }
    $etype = @{INFO='Information'; WARN='Warning'; ERROR='Error'}[$level]
    Write-EventLog -LogName Application -Source 'DevDrive-Mount' -EntryType $etype -EventId 1000 -Message $line
  } catch {}
}

try { Start-Transcript -Path ($logPath -replace '\.log$','.transcript.txt') -Append -ErrorAction SilentlyContinue | Out-Null } catch {}
Write-Log ("=== Mount-DevDrive start ===")
Write-Log ("Config: VHDX={0} | Label={1} | TargetLetter={2}" -f $vhx,$label,$letter)
Write-Log ("User: {0}" -f (whoami))

# ===== 单实例互斥，避免并发争用 VHDX =====
$globalMutexName = 'Global\MountDevDrive_VHDX'
$mutex = New-Object System.Threading.Mutex($false, $globalMutexName)
if (-not $mutex.WaitOne(0)) {
  Write-Log "检测到已有实例在运行，当前实例退出。"
  try { Stop-Transcript | Out-Null } catch {}
  exit 0
}

# ===== 基础检查 =====
if (-not (Test-Path -LiteralPath $vhx)) {
  Write-Log ("VHDX 文件不存在：{0}" -f $vhx) 'ERROR'
  try { $mutex.ReleaseMutex() } catch {}
  try { Stop-Transcript | Out-Null } catch {}
  exit 2
}

# 检查管理员权限（计划任务请使用 SYSTEM + 最高权限）
try {
  $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
  if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Log "当前会话非管理员，这会导致 Set-Disk/Set-Partition 等操作失败。请以 SYSTEM/管理员运行。" 'WARN'
  }
} catch {}

# ===== 开机延时 =====
if ($bootDelaySeconds -gt 0) {
  Write-Log ("Boot delay {0}s ..." -f $bootDelaySeconds)
  Start-Sleep -Seconds $bootDelaySeconds
}

# ===== diskpart 脚本工具 =====
function Run-DiskpartScript([string]$content){
  $tmp = Join-Path $env:TEMP ("dp_{0:yyyyMMdd_HHmmssfff}.txt" -f (Get-Date))
  $content | Set-Content -Path $tmp -Encoding ASCII
  $out = & diskpart.exe /s $tmp 2>&1
  $out -join "`r`n"
}

# （可选）系统级策略：仅在你愿意时开启（WTG 默认关闭）
if ($ensureSanOnlineAll) {
  Write-Log "设置 automount enable / SAN policy=onlineall"
  try {
    $dpOut = Run-DiskpartScript @"
automount enable
san
san policy=onlineall
"@
    $dpOut | Out-File -FilePath $logPath -Append -Encoding UTF8
  } catch { Write-Log ("设置 SAN/automount 异常："+$_.Exception.Message) 'WARN' }
}

# ===== 幂等挂载工具函数 =====
function Get-AttachedDisk([string]$path) {
  $img = Get-DiskImage -ImagePath $path -ErrorAction SilentlyContinue
  if ($img -and $img.Attached) {
    try { return Get-Disk -Number $img.Number -ErrorAction Stop } catch { return $null }
  }
  return $null
}

# ===== 幂等挂载：先查后挂；0x80070020 视为非致命（已被其他进程附加）=====
$disk = Get-AttachedDisk $vhx
if ($disk) {
  Write-Log ("检测到 VHDX 已附加：Disk {0}" -f $disk.Number)
} else {
  try {
    if (Get-Command Mount-VHD -ErrorAction SilentlyContinue) {
      Write-Log ("使用 Mount-VHD 挂载：{0}" -f $vhx)
      Mount-VHD -Path $vhx -NoDriveLetter -ErrorAction Stop | Out-Null
    } else {
      Write-Log "Mount-VHD 不可用，改用 diskpart"
      $dpOut = Run-DiskpartScript @"
select vdisk file="$vhx"
attach vdisk
"@
      $dpOut | Out-File -FilePath $logPath -Append -Encoding UTF8
    }
  } catch {
    $msg = $_.Exception.Message
    if ($msg -match '0x80070020' -or $msg -match 'being used by another process') {
      Write-Log "捕获 0x80070020：判断为已由其他进程附加，继续后续步骤。" 'WARN'
    } else {
      Write-Log ("挂载异常：" + $msg) 'ERROR'
    }
  }
  # 等待磁盘枚举
  for ($i=0; $i -lt $maxWaitAttachRetries -and -not $disk; $i++) {
    $disk = Get-AttachedDisk $vhx
    if (-not $disk) { Start-Sleep -Milliseconds $waitIntervalMs }
  }
  if (-not $disk) {
    Write-Log "未能定位到已附加的虚拟磁盘（Get-DiskImage/Get-Disk 均失败）" 'ERROR'
    try { $mutex.ReleaseMutex() } catch {}
    try { Stop-Transcript | Out-Null } catch {}
    exit 3
  }
}
Write-Log ("已找到磁盘：Number={0}, FriendlyName={1}, Offline={2}, ReadOnly={3}" -f $disk.Number,$disk.FriendlyName,$disk.IsOffline,$disk.IsReadOnly)

# ===== 联机 & 去只读 =====
$changed = $false
try {
  if ($disk.IsReadOnly) { Set-Disk -Number $disk.Number -IsReadOnly $false -ErrorAction Stop; $changed=$true }
  if ($disk.IsOffline)  { Set-Disk -Number $disk.Number -IsOffline  $false -ErrorAction Stop; $changed=$true }
} catch { Write-Log ("联机/去只读失败："+$_.Exception.Message) 'ERROR' }
if ($changed) { Start-Sleep -Seconds 1; $disk = Get-Disk -Number $disk.Number }
Write-Log ("联机状态：Offline={0}, ReadOnly={1}" -f $disk.IsOffline,$disk.IsReadOnly)

# ===== 选择分区（取容量最大的非保留分区）=====
$part = $null
try {
  $parts = Get-Partition -DiskNumber $disk.Number -ErrorAction Stop |
           Where-Object { $_.Type -ne 'Reserved' }
  $part  = $parts | Sort-Object Size -Descending | Select-Object -First 1
} catch { Write-Log ("获取分区失败："+$_.Exception.Message) 'ERROR' }

if (-not $part) {
  Write-Log "未发现可用分区（VHDX 是否已分区并格式化？）" 'ERROR'
  try { $mutex.ReleaseMutex() } catch {}
  try { Stop-Transcript | Out-Null } catch {}
  exit 4
}

# ===== 等待卷枚举（ReFS 在 WTG 上可能稍慢）=====
$vol = $null
for ($i=0; $i -lt $maxWaitVolumeRetries -and -not $vol; $i++) {
  try { $vol = $part | Get-Volume -ErrorAction SilentlyContinue } catch { $vol = $null }
  if (-not $vol) { Start-Sleep -Milliseconds $waitIntervalMs }
}
if ($vol) { Write-Log ("卷：DriveLetter={0}, Label={1}, FS={2}, Health={3}" -f $vol.DriveLetter,$vol.FileSystemLabel,$vol.FileSystem,$vol.HealthStatus) }
else      { Write-Log "卷尚未就绪，后续步骤将直接按分区操作（稍后仍会再读卷信息）" 'WARN' }

# ===== 盘符处理（尽量占用目标盘符；若被分区卷占用则挪走；若被 CD-ROM 占用则回退）=====
function Get-FreeLetter {
  ('D'..'Z') | Where-Object { -not (Get-Volume -DriveLetter $_ -ErrorAction SilentlyContinue) } | Select-Object -First 1
}
if ($part.DriveLetter -ne $letter) {
  $occupied = Get-Volume -DriveLetter $letter -ErrorAction SilentlyContinue
  if ($occupied -and $vol -and ($occupied.UniqueId -ne $vol.UniqueId) -and $occupied.DriveType -ne 'CD-ROM') {
    $alt = Get-FreeLetter
    if ($alt) {
      try {
        $op = Get-Partition -DriveLetter $occupied.DriveLetter -ErrorAction Stop
        Write-Log ("{0}: 被占用，先把该分区卷改到 {1}:" -f $letter,$alt) 'WARN'
        Set-Partition -DiskNumber $op.DiskNumber -PartitionNumber $op.PartitionNumber -NewDriveLetter $alt -ErrorAction Stop
      } catch { Write-Log ("挪走占用失败："+$_.Exception.Message) 'WARN' }
    }
  }
  try {
    Set-Partition -DiskNumber $part.DiskNumber -PartitionNumber $part.PartitionNumber -NewDriveLetter $letter -ErrorAction Stop
    Write-Log ("已将 Dev Drive 设为 {0}:\\" -f $letter)
  } catch {
    $alt = Get-FreeLetter
    Write-Log ("设置 {0}: 失败，回退到空闲盘符 {1}: —— {2}" -f $letter,$alt,$_.Exception.Message) 'WARN'
    if ($alt) { Set-Partition -DiskNumber $part.DiskNumber -PartitionNumber $part.PartitionNumber -NewDriveLetter $alt -ErrorAction SilentlyContinue }
  }
} else {
  Write-Log ("{0}: 已就位" -f $letter)
}

# ===== 卷标校正（可选）=====
try {
  $cur = Get-Volume -DriveLetter $letter -ErrorAction SilentlyContinue
  if ($cur -and $cur.FileSystemLabel -ne $label) {
    Set-Volume -DriveLetter $letter -NewFileSystemLabel $label -ErrorAction SilentlyContinue
    Write-Log ("卷标校正：{0} -> {1}" -f $cur.FileSystemLabel,$label)
  }
} catch { Write-Log ("设置卷标失败："+$_.Exception.Message) 'WARN' }

# ===== 收尾：输出最终状态 =====
$final = Get-Volume -DriveLetter $letter -ErrorAction SilentlyContinue
if ($final) {
  Write-Log ("完成：{0}: | Label={1} | FS={2} | Health={3}" -f $letter,$final.FileSystemLabel,$final.FileSystem,$final.HealthStatus)
} else {
  Write-Log ("完成：未在 {0}: 发现卷（可能回退到其它盘符），请查看上文日志" -f $letter) 'WARN'
}

Write-Log "=== Mount-DevDrive end ==="

# 释放互斥 & 结束记录
try { $mutex.ReleaseMutex() } catch {}
try { Stop-Transcript | Out-Null } catch {}
