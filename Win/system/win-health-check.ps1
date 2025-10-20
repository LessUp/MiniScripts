#Requires -Version 7.0
#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Windows系统健康检查脚本
.DESCRIPTION
    全面检查Windows系统健康状态，包括系统资源、服务、网络、文件完整性等
    支持自动修复和详细报告生成
.PARAMETER Silent
    静默运行模式，不显示交互提示
.PARAMETER AutoFix
    自动修复发现的问题
.PARAMETER OutputPath
    报告输出路径，默认为脚本目录
.EXAMPLE
    .\Windows-HealthCheck.ps1 -Silent -AutoFix
.NOTES
    作者: System Administrator
    版本: 1.0
    需要管理员权限运行
#>

param(
    [switch]$Silent,
    [switch]$AutoFix,
    [string]$OutputPath = $PSScriptRoot
)

# 全局变量
$Script:Issues = @{
    Critical = @()
    Warning = @()
    Info = @()
}
$Script:LogFile = Join-Path $OutputPath "HealthCheck_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
$Script:ReportFile = Join-Path $OutputPath "HealthCheck_Report_$(Get-Date -Format 'yyyyMMdd_HHmmss').html"

# 日志记录函数
function Write-Log {
    param(
        [string]$Message,
        [ValidateSet('Info', 'Warning', 'Error', 'Success')]
        [string]$Level = 'Info'
    )
    
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $logEntry = "[$timestamp] [$Level] $Message"
    
    # 写入日志文件
    Add-Content -Path $Script:LogFile -Value $logEntry -Encoding UTF8
    
    # 控制台输出（如果不是静默模式）
    if (-not $Silent) {
        switch ($Level) {
            'Error' { Write-Host $logEntry -ForegroundColor Red }
            'Warning' { Write-Host $logEntry -ForegroundColor Yellow }
            'Success' { Write-Host $logEntry -ForegroundColor Green }
            default { Write-Host $logEntry -ForegroundColor White }
        }
    }
}

# 添加问题到报告
function Add-Issue {
    param(
        [string]$Category,
        [string]$Description,
        [string]$Recommendation,
        [ValidateSet('Critical', 'Warning', 'Info')]
        [string]$Severity = 'Info'
    )
    
    $issue = [PSCustomObject]@{
        Category = $Category
        Description = $Description
        Recommendation = $Recommendation
        Timestamp = Get-Date
    }
    
    $Script:Issues[$Severity] += $issue
    Write-Log "[$Severity] ${Category}: $Description" -Level $Severity
}

# 检查系统资源
function Test-SystemResources {
    Write-Log "开始检查系统资源..." -Level Info
    
    try {
        # CPU使用率检查
        $cpuUsage = (Get-Counter '\Processor(_Total)\% Processor Time' -SampleInterval 1 -MaxSamples 3 | 
                    Select-Object -ExpandProperty CounterSamples | 
                    Measure-Object -Property CookedValue -Average).Average
        
        if ($cpuUsage -gt 80) {
            Add-Issue -Category "系统资源" -Description "CPU使用率过高: $([math]::Round($cpuUsage, 2))%" -Severity "Critical" -Recommendation "检查高CPU使用率进程，考虑重启或优化"
        } elseif ($cpuUsage -gt 60) {
            Add-Issue -Category "系统资源" -Description "CPU使用率较高: $([math]::Round($cpuUsage, 2))%" -Severity "Warning" -Recommendation "监控CPU使用情况"
        }
        
        # 内存使用率检查
        $memory = Get-CimInstance -ClassName Win32_OperatingSystem
        $memoryUsagePercent = [math]::Round((($memory.TotalVisibleMemorySize - $memory.FreePhysicalMemory) / $memory.TotalVisibleMemorySize) * 100, 2)
        
        if ($memoryUsagePercent -gt 90) {
            Add-Issue -Category "系统资源" -Description "内存使用率过高: $memoryUsagePercent%" -Severity "Critical" -Recommendation "关闭不必要的程序或增加内存"
        } elseif ($memoryUsagePercent -gt 80) {
            Add-Issue -Category "系统资源" -Description "内存使用率较高: $memoryUsagePercent%" -Severity "Warning" -Recommendation "监控内存使用情况"
        }
        
        # 磁盘空间检查
        $disks = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DriveType=3"
        foreach ($disk in $disks) {
            $freeSpacePercent = [math]::Round(($disk.FreeSpace / $disk.Size) * 100, 2)
            if ($freeSpacePercent -lt 10) {
                Add-Issue -Category "磁盘空间" -Description "磁盘 $($disk.DeviceID) 空间不足: $freeSpacePercent% 可用" -Severity "Critical" -Recommendation "清理磁盘空间或扩展存储"
            } elseif ($freeSpacePercent -lt 20) {
                Add-Issue -Category "磁盘空间" -Description "磁盘 $($disk.DeviceID) 空间较少: $freeSpacePercent% 可用" -Severity "Warning" -Recommendation "考虑清理不必要的文件"
            }
        }
        
        Write-Log "系统资源检查完成" -Level Success
    }
    catch {
        Write-Log "系统资源检查失败: $($_.Exception.Message)" -Level Error
    }
}

# 检查系统服务
function Test-SystemServices {
    Write-Log "开始检查系统服务..." -Level Info
    
    # 关键服务列表
    $criticalServices = @(
        'Winmgmt',      # Windows Management Instrumentation
        'EventLog',     # Windows Event Log
        'RpcSs',        # Remote Procedure Call (RPC)
        'Dhcp',         # DHCP Client
        'Dnscache',     # DNS Client
        'LanmanServer', # Server
        'LanmanWorkstation', # Workstation
        'Spooler',      # Print Spooler
        'Themes',       # Themes
        'AudioSrv',     # Windows Audio
        'BITS',         # Background Intelligent Transfer Service
        'Wuauserv'      # Windows Update
    )
    
    try {
        foreach ($serviceName in $criticalServices) {
            $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
            if ($service) {
                if ($service.Status -ne 'Running' -and $service.StartType -ne 'Disabled') {
                    Add-Issue -Category "系统服务" -Description "关键服务 '$serviceName' 未运行 (状态: $($service.Status))" -Severity "Critical" -Recommendation "启动服务: Start-Service -Name '$serviceName'"
                    
                    # 自动修复
                    if ($AutoFix) {
                        try {
                            Start-Service -Name $serviceName
                            Write-Log "已自动启动服务: $serviceName" -Level Success
                        }
                        catch {
                            Write-Log "无法启动服务 $serviceName : $($_.Exception.Message)" -Level Error
                        }
                    }
                }
            }
            else {
                Add-Issue -Category "系统服务" -Description "关键服务 '$serviceName' 不存在" -Severity "Warning" -Recommendation "检查服务是否已被卸载或名称是否正确"
            }
        }
        
        Write-Log "系统服务检查完成" -Level Success
    }
    catch {
        Write-Log "系统服务检查失败: $($_.Exception.Message)" -Level Error
    }
}

# 检查网络连接
function Test-NetworkConnectivity {
    Write-Log "开始检查网络连接..." -Level Info
    
    try {
        # 检查网络适配器
        $adapters = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' }
        if ($adapters.Count -eq 0) {
            Add-Issue -Category "网络连接" -Description "没有活动的网络适配器" -Severity "Critical" -Recommendation "检查网络硬件和驱动程序"
        }
        
        # DNS解析测试
        try {
            $dnsTest = Resolve-DnsName -Name "www.microsoft.com" -ErrorAction Stop
            Write-Log "DNS解析正常" -Level Success
        }
        catch {
            Add-Issue -Category "网络连接" -Description "DNS解析失败" -Severity "Critical" -Recommendation "检查DNS设置，尝试: ipconfig /flushdns"
            
            if ($AutoFix) {
                try {
                    Clear-DnsClientCache
                    Write-Log "已清理DNS缓存" -Level Success
                }
                catch {
                    Write-Log "清理DNS缓存失败: $($_.Exception.Message)" -Level Error
                }
            }
        }
        
        # 网络连通性测试
        $testHosts = @('8.8.8.8', '1.1.1.1', 'www.baidu.com')
        $failedTests = 0
        
        foreach ($host in $testHosts) {
            if (-not (Test-NetConnection -ComputerName $host -Port 80 -InformationLevel Quiet -WarningAction SilentlyContinue)) {
                $failedTests++
            }
        }
        
        if ($failedTests -eq $testHosts.Count) {
            Add-Issue -Category "网络连接" -Description "所有网络连通性测试失败" -Severity "Critical" -Recommendation "检查网络连接和防火墙设置"
        } elseif ($failedTests -gt 0) {
            Add-Issue -Category "网络连接" -Description "部分网络连通性测试失败" -Severity "Warning" -Recommendation "检查特定网络路径"
        }
        
        Write-Log "网络连接检查完成" -Level Success
    }
    catch {
        Write-Log "网络连接检查失败: $($_.Exception.Message)" -Level Error
    }
}

# 检查系统文件完整性
function Test-SystemFileIntegrity {
    Write-Log "开始检查系统文件完整性..." -Level Info

    try {
        # 运行SFC扫描
        Write-Log "正在运行系统文件检查器 (SFC)..." -Level Info
        $sfcResult = & sfc /scannow 2>&1

        if ($LASTEXITCODE -eq 0) {
            Write-Log "系统文件完整性检查完成，未发现问题" -Level Success
        } else {
            Add-Issue -Category "系统文件" -Description "系统文件检查器发现问题" -Severity "Warning" -Recommendation "查看SFC日志: %windir%\Logs\CBS\CBS.log"
        }

        # 检查DISM健康状态
        Write-Log "正在检查Windows映像健康状态..." -Level Info
        $dismResult = & DISM /Online /Cleanup-Image /CheckHealth 2>&1

        if ($LASTEXITCODE -ne 0) {
            Add-Issue -Category "系统文件" -Description "Windows映像可能存在损坏" -Severity "Critical" -Recommendation "运行: DISM /Online /Cleanup-Image /RestoreHealth"

            if ($AutoFix) {
                Write-Log "正在尝试修复Windows映像..." -Level Info
                & DISM /Online /Cleanup-Image /RestoreHealth
            }
        }

        Write-Log "系统文件完整性检查完成" -Level Success
    }
    catch {
        Write-Log "系统文件完整性检查失败: $($_.Exception.Message)" -Level Error
    }
}

# 检查Windows更新状态
function Test-WindowsUpdate {
    Write-Log "开始检查Windows更新状态..." -Level Info

    try {
        # 检查Windows Update服务
        $wuService = Get-Service -Name 'wuauserv' -ErrorAction SilentlyContinue
        if ($wuService.Status -ne 'Running') {
            Add-Issue -Category "Windows更新" -Description "Windows Update服务未运行" -Severity "Warning" -Recommendation "启动Windows Update服务"
        }

        # 使用PSWindowsUpdate模块检查更新（如果可用）
        if (Get-Module -ListAvailable -Name PSWindowsUpdate) {
            Import-Module PSWindowsUpdate -Force
            $updates = Get-WUList -MicrosoftUpdate

            if ($updates.Count -gt 0) {
                $criticalUpdates = $updates | Where-Object { $_.MsrcSeverity -eq 'Critical' }
                $importantUpdates = $updates | Where-Object { $_.MsrcSeverity -eq 'Important' }

                if ($criticalUpdates.Count -gt 0) {
                    Add-Issue -Category "Windows更新" -Description "有 $($criticalUpdates.Count) 个关键更新待安装" -Severity "Critical" -Recommendation "立即安装关键安全更新"
                }

                if ($importantUpdates.Count -gt 0) {
                    Add-Issue -Category "Windows更新" -Description "有 $($importantUpdates.Count) 个重要更新待安装" -Severity "Warning" -Recommendation "安排时间安装重要更新"
                }
            }
        } else {
            # 使用WMI检查更新历史
            $updateSession = New-Object -ComObject Microsoft.Update.Session
            $updateSearcher = $updateSession.CreateUpdateSearcher()
            $searchResult = $updateSearcher.Search("IsInstalled=0")

            if ($searchResult.Updates.Count -gt 0) {
                Add-Issue -Category "Windows更新" -Description "有 $($searchResult.Updates.Count) 个更新待安装" -Severity "Warning" -Recommendation "检查并安装可用更新"
            }
        }

        Write-Log "Windows更新状态检查完成" -Level Success
    }
    catch {
        Write-Log "Windows更新状态检查失败: $($_.Exception.Message)" -Level Error
    }
}

# 分析事件日志
function Test-EventLogs {
    Write-Log "开始分析事件日志..." -Level Info

    try {
        $endTime = Get-Date
        $startTime = $endTime.AddDays(-7)  # 检查最近7天的日志

        # 检查系统日志中的错误
        $systemErrors = Get-WinEvent -FilterHashtable @{
            LogName = 'System'
            Level = 1,2  # Critical and Error
            StartTime = $startTime
            EndTime = $endTime
        } -MaxEvents 50 -ErrorAction SilentlyContinue

        if ($systemErrors.Count -gt 10) {
            Add-Issue -Category "事件日志" -Description "系统日志中有 $($systemErrors.Count) 个错误事件（最近7天）" -Severity "Warning" -Recommendation "查看事件查看器中的系统日志详情"
        }

        # 检查应用程序日志中的错误
        $appErrors = Get-WinEvent -FilterHashtable @{
            LogName = 'Application'
            Level = 1,2  # Critical and Error
            StartTime = $startTime
            EndTime = $endTime
        } -MaxEvents 50 -ErrorAction SilentlyContinue

        if ($appErrors.Count -gt 20) {
            Add-Issue -Category "事件日志" -Description "应用程序日志中有 $($appErrors.Count) 个错误事件（最近7天）" -Severity "Warning" -Recommendation "查看事件查看器中的应用程序日志详情"
        }

        # 检查安全日志中的登录失败
        $securityEvents = Get-WinEvent -FilterHashtable @{
            LogName = 'Security'
            ID = 4625  # Failed logon
            StartTime = $startTime
            EndTime = $endTime
        } -MaxEvents 20 -ErrorAction SilentlyContinue

        if ($securityEvents.Count -gt 10) {
            Add-Issue -Category "安全" -Description "检测到 $($securityEvents.Count) 次登录失败（最近7天）" -Severity "Warning" -Recommendation "检查是否存在暴力破解攻击"
        }

        Write-Log "事件日志分析完成" -Level Success
    }
    catch {
        Write-Log "事件日志分析失败: $($_.Exception.Message)" -Level Error
    }
}

# 检查启动项
function Test-StartupPrograms {
    Write-Log "开始检查启动项..." -Level Info

    try {
        # 检查注册表启动项
        $startupLocations = @(
            'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run',
            'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run',
            'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run'
        )

        $startupCount = 0
        foreach ($location in $startupLocations) {
            if (Test-Path $location) {
                $items = Get-ItemProperty $location -ErrorAction SilentlyContinue
                if ($items) {
                    $startupCount += ($items.PSObject.Properties | Where-Object { $_.Name -notlike 'PS*' }).Count
                }
            }
        }

        # 检查启动文件夹
        $startupFolders = @(
            "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup",
            "$env:ALLUSERSPROFILE\Microsoft\Windows\Start Menu\Programs\Startup"
        )

        foreach ($folder in $startupFolders) {
            if (Test-Path $folder) {
                $startupCount += (Get-ChildItem $folder -File).Count
            }
        }

        if ($startupCount -gt 15) {
            Add-Issue -Category "启动项" -Description "启动项过多: $startupCount 个程序" -Severity "Warning" -Recommendation "使用任务管理器禁用不必要的启动程序"
        }

        Write-Log "启动项检查完成，发现 $startupCount 个启动项" -Level Success
    }
    catch {
        Write-Log "启动项检查失败: $($_.Exception.Message)" -Level Error
    }
}

# 清理临时文件
function Invoke-TempFileCleanup {
    Write-Log "开始清理临时文件..." -Level Info

    if (-not $AutoFix) {
        Write-Log "跳过临时文件清理（需要 -AutoFix 参数）" -Level Info
        return
    }

    try {
        $cleanupPaths = @(
            "$env:TEMP",
            "$env:WINDIR\Temp",
            "$env:LOCALAPPDATA\Temp",
            "$env:USERPROFILE\AppData\Local\Microsoft\Windows\Temporary Internet Files",
            "$env:LOCALAPPDATA\Microsoft\Windows\INetCache"
        )

        $totalCleaned = 0
        $totalSize = 0

        foreach ($path in $cleanupPaths) {
            if (Test-Path $path) {
                try {
                    $files = Get-ChildItem $path -Recurse -File -ErrorAction SilentlyContinue |
                             Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-7) }

                    foreach ($file in $files) {
                        try {
                            $totalSize += $file.Length
                            Remove-Item $file.FullName -Force -ErrorAction SilentlyContinue
                            $totalCleaned++
                        }
                        catch {
                            # 忽略无法删除的文件
                        }
                    }
                }
                catch {
                    Write-Log "无法清理路径: $path" -Level Warning
                }
            }
        }

        # 清理回收站
        try {
            Clear-RecycleBin -Force -ErrorAction SilentlyContinue
            Write-Log "已清理回收站" -Level Success
        }
        catch {
            Write-Log "清理回收站失败: $($_.Exception.Message)" -Level Warning
        }

        # 运行磁盘清理
        try {
            & cleanmgr /sagerun:1 2>&1 | Out-Null
            Write-Log "已运行磁盘清理工具" -Level Success
        }
        catch {
            Write-Log "运行磁盘清理工具失败" -Level Warning
        }

        $sizeMB = [math]::Round($totalSize / 1MB, 2)
        Write-Log "临时文件清理完成，删除了 $totalCleaned 个文件，释放了 $sizeMB MB 空间" -Level Success

        Add-Issue -Category "系统维护" -Description "已清理 $totalCleaned 个临时文件，释放 $sizeMB MB 空间" -Severity "Info" -Recommendation "定期清理临时文件以保持系统性能"
    }
    catch {
        Write-Log "临时文件清理失败: $($_.Exception.Message)" -Level Error
    }
}

# 生成HTML报告
function New-HealthReport {
    Write-Log "正在生成健康检查报告..." -Level Info

    try {
        $systemInfo = Get-CimInstance -ClassName Win32_ComputerSystem
        $osInfo = Get-CimInstance -ClassName Win32_OperatingSystem
        $reportTime = Get-Date -Format 'yyyy年MM月dd日 HH:mm:ss'

        $html = @"
<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Windows系统健康检查报告</title>
    <style>
        body { font-family: 'Microsoft YaHei', Arial, sans-serif; margin: 20px; background-color: #f5f5f5; }
        .container { max-width: 1200px; margin: 0 auto; background-color: white; padding: 20px; border-radius: 8px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
        .header { text-align: center; border-bottom: 2px solid #007acc; padding-bottom: 20px; margin-bottom: 30px; }
        .header h1 { color: #007acc; margin: 0; }
        .system-info { background-color: #f8f9fa; padding: 15px; border-radius: 5px; margin-bottom: 20px; }
        .section { margin-bottom: 30px; }
        .section h2 { color: #333; border-left: 4px solid #007acc; padding-left: 10px; }
        .issue-critical { background-color: #f8d7da; border: 1px solid #f5c6cb; border-radius: 5px; padding: 10px; margin: 10px 0; }
        .issue-warning { background-color: #fff3cd; border: 1px solid #ffeaa7; border-radius: 5px; padding: 10px; margin: 10px 0; }
        .issue-info { background-color: #d1ecf1; border: 1px solid #bee5eb; border-radius: 5px; padding: 10px; margin: 10px 0; }
        .issue-title { font-weight: bold; margin-bottom: 5px; }
        .issue-desc { margin-bottom: 5px; }
        .issue-rec { font-style: italic; color: #666; }
        .summary { display: flex; justify-content: space-around; margin-bottom: 20px; }
        .summary-item { text-align: center; padding: 15px; border-radius: 5px; min-width: 120px; }
        .critical-count { background-color: #dc3545; color: white; }
        .warning-count { background-color: #ffc107; color: black; }
        .info-count { background-color: #17a2b8; color: white; }
        .no-issues { background-color: #28a745; color: white; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>Windows系统健康检查报告</h1>
            <p>生成时间: $reportTime</p>
        </div>

        <div class="system-info">
            <h3>系统信息</h3>
            <p><strong>计算机名:</strong> $($systemInfo.Name)</p>
            <p><strong>操作系统:</strong> $($osInfo.Caption) $($osInfo.Version)</p>
            <p><strong>总内存:</strong> $([math]::Round($osInfo.TotalVisibleMemorySize / 1MB, 2)) GB</p>
            <p><strong>制造商:</strong> $($systemInfo.Manufacturer)</p>
            <p><strong>型号:</strong> $($systemInfo.Model)</p>
        </div>

        <div class="summary">
            <div class="summary-item critical-count">
                <h3>$($Script:Issues.Critical.Count)</h3>
                <p>严重问题</p>
            </div>
            <div class="summary-item warning-count">
                <h3>$($Script:Issues.Warning.Count)</h3>
                <p>警告</p>
            </div>
            <div class="summary-item info-count">
                <h3>$($Script:Issues.Info.Count)</h3>
                <p>信息</p>
            </div>
        </div>
"@

        # 添加严重问题
        if ($Script:Issues.Critical.Count -gt 0) {
            $html += @"
        <div class="section">
            <h2>严重问题 ($($Script:Issues.Critical.Count))</h2>
"@
            foreach ($issue in $Script:Issues.Critical) {
                $html += @"
            <div class="issue-critical">
                <div class="issue-title">[$($issue.Category)] $($issue.Description)</div>
                <div class="issue-rec">建议: $($issue.Recommendation)</div>
            </div>
"@
            }
            $html += "        </div>`n"
        }

        # 添加警告
        if ($Script:Issues.Warning.Count -gt 0) {
            $html += @"
        <div class="section">
            <h2>警告 ($($Script:Issues.Warning.Count))</h2>
"@
            foreach ($issue in $Script:Issues.Warning) {
                $html += @"
            <div class="issue-warning">
                <div class="issue-title">[$($issue.Category)] $($issue.Description)</div>
                <div class="issue-rec">建议: $($issue.Recommendation)</div>
            </div>
"@
            }
            $html += "        </div>`n"
        }

        # 添加信息
        if ($Script:Issues.Info.Count -gt 0) {
            $html += @"
        <div class="section">
            <h2>信息 ($($Script:Issues.Info.Count))</h2>
"@
            foreach ($issue in $Script:Issues.Info) {
                $html += @"
            <div class="issue-info">
                <div class="issue-title">[$($issue.Category)] $($issue.Description)</div>
                <div class="issue-rec">建议: $($issue.Recommendation)</div>
            </div>
"@
            }
            $html += "        </div>`n"
        }

        # 如果没有问题
        if ($Script:Issues.Critical.Count -eq 0 -and $Script:Issues.Warning.Count -eq 0 -and $Script:Issues.Info.Count -eq 0) {
            $html += @"
        <div class="section">
            <div class="summary-item no-issues">
                <h2>✓ 系统健康状况良好</h2>
                <p>未发现任何问题</p>
            </div>
        </div>
"@
        }

        $html += @"
        <div class="section">
            <h2>建议的维护操作</h2>
            <ul>
                <li>定期运行Windows更新</li>
                <li>定期清理临时文件和磁盘碎片整理</li>
                <li>监控系统资源使用情况</li>
                <li>定期备份重要数据</li>
                <li>保持防病毒软件更新</li>
            </ul>
        </div>

        <div style="text-align: center; margin-top: 30px; color: #666; font-size: 12px;">
            <p>报告由Windows健康检查脚本生成 | 日志文件: $($Script:LogFile)</p>
        </div>
    </div>
</body>
</html>
"@

        # 保存HTML报告
        $html | Out-File -FilePath $Script:ReportFile -Encoding UTF8
        Write-Log "HTML报告已生成: $Script:ReportFile" -Level Success

        # 如果不是静默模式，打开报告
        if (-not $Silent) {
            Start-Process $Script:ReportFile
        }
    }
    catch {
        Write-Log "生成报告失败: $($_.Exception.Message)" -Level Error
    }
}

# 主函数
function Start-HealthCheck {
    param(
        [switch]$Silent,
        [switch]$AutoFix,
        [string]$OutputPath
    )

    # 初始化
    Write-Log "开始Windows系统健康检查..." -Level Info
    Write-Log "脚本版本: 1.0" -Level Info
    Write-Log "运行模式: $(if($Silent){'静默'}else{'交互'}) | 自动修复: $(if($AutoFix){'启用'}else{'禁用'})" -Level Info

    # 检查管理员权限
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Log "错误: 此脚本需要管理员权限运行" -Level Error
        throw "需要管理员权限"
    }

    try {
        # 执行各项检查
        $checkFunctions = @(
            'Test-SystemResources',
            'Test-SystemServices',
            'Test-NetworkConnectivity',
            'Test-SystemFileIntegrity',
            'Test-WindowsUpdate',
            'Test-EventLogs',
            'Test-StartupPrograms'
        )

        $totalChecks = $checkFunctions.Count
        $currentCheck = 0

        foreach ($checkFunction in $checkFunctions) {
            $currentCheck++
            if (-not $Silent) {
                Write-Progress -Activity "系统健康检查" -Status "正在执行: $checkFunction" -PercentComplete (($currentCheck / $totalChecks) * 100)
            }

            try {
                & $checkFunction
            }
            catch {
                Write-Log "执行 $checkFunction 时出错: $($_.Exception.Message)" -Level Error
            }
        }

        # 执行清理操作
        if ($AutoFix) {
            if (-not $Silent) {
                Write-Progress -Activity "系统健康检查" -Status "正在清理临时文件..." -PercentComplete 90
            }
            Invoke-TempFileCleanup
        }

        # 生成报告
        if (-not $Silent) {
            Write-Progress -Activity "系统健康检查" -Status "正在生成报告..." -PercentComplete 95
        }
        New-HealthReport

        # 完成进度条
        if (-not $Silent) {
            Write-Progress -Activity "系统健康检查" -Completed
        }

        # 显示摘要
        $totalIssues = $Script:Issues.Critical.Count + $Script:Issues.Warning.Count + $Script:Issues.Info.Count
        Write-Log "健康检查完成!" -Level Success
        Write-Log "发现问题总数: $totalIssues (严重: $($Script:Issues.Critical.Count), 警告: $($Script:Issues.Warning.Count), 信息: $($Script:Issues.Info.Count))" -Level Info
        Write-Log "报告文件: $Script:ReportFile" -Level Info
        Write-Log "日志文件: $Script:LogFile" -Level Info

        # 如果有严重问题，返回非零退出代码
        if ($Script:Issues.Critical.Count -gt 0) {
            Write-Log "检测到严重问题，建议立即处理" -Level Warning
            exit 1
        }
    }
    catch {
        Write-Log "健康检查过程中发生错误: $($_.Exception.Message)" -Level Error
        exit 2
    }
}

# 显示帮助信息
function Show-Help {
    Write-Host @"
Windows系统健康检查脚本 v1.0
========================================

用法:
    .\Windows-HealthCheck.ps1 [参数]

参数:
    -Silent         静默运行，不显示交互提示
    -AutoFix        自动修复发现的问题
    -OutputPath     指定报告输出路径（默认为脚本目录）
    -Help           显示此帮助信息

示例:
    .\Windows-HealthCheck.ps1
    .\Windows-HealthCheck.ps1 -Silent -AutoFix
    .\Windows-HealthCheck.ps1 -OutputPath "C:\Reports"

功能:
    ✓ 系统资源检查 (CPU、内存、磁盘)
    ✓ 系统服务状态检查
    ✓ 网络连接测试
    ✓ 系统文件完整性检查
    ✓ Windows更新状态
    ✓ 事件日志分析
    ✓ 启动项检查
    ✓ 临时文件清理
    ✓ 详细HTML报告生成

注意:
    - 需要管理员权限运行
    - 建议定期运行以维护系统健康
    - 自动修复功能会修改系统设置，请谨慎使用

"@ -ForegroundColor Cyan
}

# 脚本入口点
try {
    # 检查是否请求帮助
    if ($args -contains '-Help' -or $args -contains '--help' -or $args -contains '/?') {
        Show-Help
        exit 0
    }

    # 创建输出目录
    if (-not (Test-Path $OutputPath)) {
        New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null
    }

    # 启动健康检查
    Start-HealthCheck -Silent:$Silent -AutoFix:$AutoFix -OutputPath $OutputPath
}
catch {
    Write-Host "脚本执行失败: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "请以管理员身份运行此脚本" -ForegroundColor Yellow
    exit 3
}

# 脚本结束
Write-Host "`n按任意键退出..." -ForegroundColor Green
if (-not $Silent) {
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}
