# 使用说明

1. 在 C 盘创建脚本目录并保存脚本 `C:\Scripts\Mount-DevDrive.ps1`。
2. 注册计划任务（需在管理员 PowerShell 中执行）：

   ```powershell
   # 确保目录存在
   New-Item -ItemType Directory -Path C:\Scripts -Force | Out-Null

   # 重建任务（若已存在会先删除）
   $taskName = "Mount Dev Drive (VHDX)"
   try { Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue } catch {}

   $act = New-ScheduledTaskAction  -Execute 'powershell.exe' `
          -Argument '-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "C:\Scripts\Mount-DevDrive.ps1"'
   $trg = New-ScheduledTaskTrigger -AtStartup
   $pri = New-ScheduledTaskPrincipal -UserId "SYSTEM" -RunLevel Highest
   $set = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries

   Register-ScheduledTask -TaskName $taskName -Action $act -Trigger $trg -Principal $pri -Settings $set `
     -Description "Attach C:\Data\DevDrive\DevDrive.vhdx and set D: (label Dev)"
   ```

3. 测试脚本：

   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File "C:\Scripts\Mount-DevDrive.ps1"
   ```

4. 配置系统盘策略（只需执行一次，可避免虚拟盘默认离线）：

   ```text
   diskpart
   automount enable
   san
   san policy=onlineall
   exit
   ```