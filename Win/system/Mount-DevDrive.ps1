# Mount-DevDrive.ps1  —— 适用于 Windows To Go / Dev Drive (ReFS) 的 VHDX
# 你当前配置：Label=Dev、Letter=D、VHDX=C:\Data\DevDrive\DevDrive.vhdx
$ErrorActionPreference = 'Stop'
$vhx    = 'C:\Data\DevDrive\DevDrive.vhdx'
$label  = 'Dev'
$letter = 'D'

 $logPath = 'C:\Data\DevDrive\Mount-DevDrive.log'
 try { $null = New-Item -ItemType Directory -Path (Split-Path $logPath -Parent) -Force } catch {}
 function Write-Log { param([string]$Message,[string]$Level='INFO') $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'; $line = "[$ts][$Level] $Message"; try { Add-Content -Path $logPath -Value $line -Encoding UTF8 } catch {}; Write-Output $line }
 $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
 if (-not $isAdmin) { Write-Log "当前会话非管理员权限，可能导致磁盘联机/分区操作失败。" 'WARN' }
 if (-not (Test-Path -LiteralPath $vhx)) { Write-Log "未找到VHDX文件：$vhx" 'ERROR'; exit 2 }
 try { Start-Service -Name 'vds' -ErrorAction SilentlyContinue } catch {}
 Write-Log "开始执行，VHDX=$vhx，预期卷标=$label，预期盘符=$letter"
 $mountBy = ''
 function Get-FreeLetter {
  $all = 'D','E','F','G','H','I','J','K','L','M','N','O','P','Q','R','S','T','U','V','W','X','Y','Z'
  return ($all | Where-Object { -not (Get-Volume -DriveLetter $_ -ErrorAction SilentlyContinue) })[0]
}

# 1) 挂载 VHDX（优先用 Mount-VHD；没有该命令则退回 diskpart）
if (Get-Command Mount-VHD -ErrorAction SilentlyContinue) {
  Write-Log "使用 Mount-VHD 挂载：$vhx"
  $vd = Mount-VHD -Path $vhx -PassThru
  $mountBy = 'Mount-VHD'
} else {
  Write-Log "使用 diskpart 挂载：$vhx"
  $tmp = Join-Path $env:TEMP 'attach-devdrive.txt'
  @"
select vdisk file="$vhx"
attach vdisk
"@ | Set-Content -Path $tmp -Encoding ASCII
  Start-Process -FilePath diskpart.exe -ArgumentList "/s `"$tmp`"" -Wait -NoNewWindow
  $mountBy = 'diskpart'
}

Start-Sleep -Seconds 1
Write-Log "挂载后等待 1 秒完成设备枚举（方式：$mountBy）"

# 2) 尝试按卷标找到目标卷；找不到就拿新挂载磁盘的第一个分区卷
Write-Log "按卷标查找卷：$label"
$vol = $null
for ($i=0; $i -lt 12 -and -not $vol; $i++) {
  $vol = Get-Volume -FileSystemLabel $label -ErrorAction SilentlyContinue
  if (-not $vol) { Start-Sleep -Milliseconds 500 }
}
if (-not $vol) {
  Write-Log "按卷标未找到，改为按挂载的磁盘获取卷"
  $disk = $null
  try { $disk = (Get-DiskImage -ImagePath $vhx | Get-Disk) } catch {}
  if (-not $disk) { $disk = Get-Disk | Sort-Object -Property Number -Descending | Select-Object -First 1 }
  if ($disk.IsOffline -or $disk.IsReadOnly) { Write-Log "磁盘离线或只读，尝试联机/去只读：Disk $($disk.Number)"; Set-Disk -Number $disk.Number -IsOffline $false -IsReadOnly $false }
  Start-Sleep -Seconds 1
  $part = Get-Partition -DiskNumber $disk.Number | Sort-Object PartitionNumber | Select-Object -First 1
  $vol  = $part | Get-Volume
  if ($vol) { Write-Log "已获取卷：DriveLetter=$($vol.DriveLetter) Label=$($vol.FileSystemLabel) FileSystem=$($vol.FileSystem)" }
}

# 3) 确保磁盘联机/可写
$disk = ($vol | Get-Partition | Select-Object -First 1 | Get-Disk)
Write-Log "检查磁盘状态：Disk $($disk.Number) IsOffline=$($disk.IsOffline) IsReadOnly=$($disk.IsReadOnly)"
if ($disk.IsOffline -or $disk.IsReadOnly) {
  Write-Log "尝试联机并清除只读：Disk $($disk.Number)"
  Set-Disk -Number $disk.Number -IsOffline $false -IsReadOnly $false
  Start-Sleep -Seconds 1
  $d2 = Get-Disk -Number $disk.Number
  Write-Log "联机后状态：IsOffline=$($d2.IsOffline) IsReadOnly=$($d2.IsReadOnly)"
}

# 4) 固定盘符为 D:（若 D 被别的“分区卷”占用则顺手挪走；CD-ROM占用则回退到空闲盘符）
$part = $vol | Get-Partition | Select-Object -First 1
Write-Log "当前分区盘符=$($part.DriveLetter)，目标盘符=$letter"
if ($part.DriveLetter -ne $letter) {
  Write-Log "尝试设置盘符为 $letter"
  $occupied = Get-Volume -DriveLetter $letter -ErrorAction SilentlyContinue
  if ($occupied -and $occupied.UniqueId -ne $vol.UniqueId -and $occupied.DriveType -ne 'CD-ROM') {
    $alt = Get-FreeLetter
    Write-Log "盘符 $letter 被占用（类型=$($occupied.DriveType)），将其临时挪到 $alt"
    $op  = Get-Partition -DriveLetter $occupied.DriveLetter -ErrorAction SilentlyContinue
    if ($op) { Set-Partition -DiskNumber $op.DiskNumber -PartitionNumber $op.PartitionNumber -NewDriveLetter $alt -ErrorAction SilentlyContinue }
    if ($op) { Write-Log "已将原盘从 $letter 挪到 $alt" }
  }
  try {
    Set-Partition -DiskNumber $part.DiskNumber -PartitionNumber $part.PartitionNumber -NewDriveLetter $letter -ErrorAction Stop
    Write-Log "已将盘符设置为 $letter"
  } catch {
    $alt = Get-FreeLetter
    Write-Log "设置盘符为 $letter 失败，改用空闲盘符 $alt" 'WARN'
    Set-Partition -DiskNumber $part.DiskNumber -PartitionNumber $part.PartitionNumber -NewDriveLetter $alt
    Write-Log "已将盘符设置为 $alt"
  }
}

# 5) 校正卷标（可选）
try {
  $cur = Get-Volume -DriveLetter $letter -ErrorAction SilentlyContinue
  if ($cur -and $cur.FileSystemLabel -ne $label) {
    Write-Log "当前卷标=$($cur.FileSystemLabel)，目标=$label"
    Set-Volume -DriveLetter $letter -NewFileSystemLabel $label
    Write-Log "已更新卷标为 $label"
  }
} catch {}
try { $cur2 = Get-Volume -DriveLetter $letter -ErrorAction SilentlyContinue; if ($cur2) { Write-Log "完成：DriveLetter=$($cur2.DriveLetter) Label=$($cur2.FileSystemLabel) FileSystem=$($cur2.FileSystem) Health=$($cur2.HealthStatus)" } } catch {}

