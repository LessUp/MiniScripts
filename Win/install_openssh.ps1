# 一键安装与配置 OpenSSH Server
Write-Host "Installing OpenSSH Server..." -ForegroundColor Cyan
Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0

Write-Host "Starting and enabling sshd service..." -ForegroundColor Cyan
Start-Service sshd
Set-Service -Name sshd -StartupType 'Automatic'

Write-Host "Allowing SSH through firewall..." -ForegroundColor Cyan
New-NetFirewallRule -Name "OpenSSH" -DisplayName "OpenSSH Server (sshd)" -Protocol TCP -LocalPort 22 -Action Allow

Write-Host "Installation and configuration completed!" -ForegroundColor Green
