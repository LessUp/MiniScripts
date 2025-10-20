# Mount-DevDrive.ps1  —— 适用于 Windows To Go / Dev Drive (ReFS) 的 VHDX
# 你当前配置：Label=Dev、Letter=D、VHDX=C:\Data\DevDrive\DevDrive.vhdx
$ErrorActionPreference = 'Stop'
$vhx    = 'C:\Data\DevDrive\DevDrive.vhdx'
$label  = 'Dev'
$letter = 'D'

function Get-FreeLetter {
  $all = 'D','E','F','G','H','I','J','K','L','M','N','O','P','Q','R','S','T','U','V','W','X','Y','Z'
  return ($all | Where-Object { -not (Get-Volume -DriveLetter $_ -ErrorAction SilentlyContinue) })[0]
}

# 1) 挂载 VHDX（优先用 Mount-VHD；没有该命令则退回 diskpart）
if (Get-Command Mount-VHD -ErrorAction SilentlyContinue) {
  $vd = Mount-VHD -Path $vhx -PassThru
} else {
  $tmp = Join-Path $env:TEMP 'attach-devdrive.txt'
  @"
select vdisk file="$vhx"
attach vdisk
"@ | Set-Content -Path $tmp -Encoding ASCII
  Start-Process -FilePath diskpart.exe -ArgumentList "/s `"$tmp`"" -Wait -NoNewWindow
}

Start-Sleep -Seconds 1

# 2) 尝试按卷标找到目标卷；找不到就拿新挂载磁盘的第一个分区卷
$vol = $null
for ($i=0; $i -lt 12 -and -not $vol; $i++) {
  $vol = Get-Volume -FileSystemLabel $label -ErrorAction SilentlyContinue
  if (-not $vol) { Start-Sleep -Milliseconds 500 }
}
if (-not $vol) {
  $disk = Get-Disk | Sort-Object -Property Number -Descending | Select-Object -First 1
  if ($disk.IsOffline -or $disk.IsReadOnly) { Set-Disk -Number $disk.Number -IsOffline $false -IsReadOnly $false }
  Start-Sleep -Seconds 1
  $part = Get-Partition -DiskNumber $disk.Number | Sort-Object PartitionNumber | Select-Object -First 1
  $vol  = $part | Get-Volume
}

# 3) 确保磁盘联机/可写
$disk = ($vol | Get-Partition | Select-Object -First 1 | Get-Disk)
if ($disk.IsOffline -or $disk.IsReadOnly) {
  Set-Disk -Number $disk.Number -IsOffline $false -IsReadOnly $false
  Start-Sleep -Seconds 1
}

# 4) 固定盘符为 D:（若 D 被别的“分区卷”占用则顺手挪走；CD-ROM占用则回退到空闲盘符）
$part = $vol | Get-Partition | Select-Object -First 1
if ($part.DriveLetter -ne $letter) {
  $occupied = Get-Volume -DriveLetter $letter -ErrorAction SilentlyContinue
  if ($occupied -and $occupied.UniqueId -ne $vol.UniqueId -and $occupied.DriveType -ne 'CD-ROM') {
    $alt = Get-FreeLetter
    $op  = Get-Partition -DriveLetter $occupied.DriveLetter -ErrorAction SilentlyContinue
    if ($op) { Set-Partition -DiskNumber $op.DiskNumber -PartitionNumber $op.PartitionNumber -NewDriveLetter $alt -ErrorAction SilentlyContinue }
  }
  try {
    Set-Partition -DiskNumber $part.DiskNumber -PartitionNumber $part.PartitionNumber -NewDriveLetter $letter -ErrorAction Stop
  } catch {
    $alt = Get-FreeLetter
    Set-Partition -DiskNumber $part.DiskNumber -PartitionNumber $part.PartitionNumber -NewDriveLetter $alt
  }
}

# 5) 校正卷标（可选）
try {
  $cur = Get-Volume -DriveLetter $letter -ErrorAction SilentlyContinue
  if ($cur -and $cur.FileSystemLabel -ne $label) {
    Set-Volume -DriveLetter $letter -NewFileSystemLabel $label
  }
} catch {}
