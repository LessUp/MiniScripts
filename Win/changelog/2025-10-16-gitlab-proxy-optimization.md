# GitLab 代理与 SSH/Git 配置优化（Windows 专用）

## 变更摘要
- 优化 `gitlab-proxy/start-proxy.ps1`
  - 自动发现 `ssh.exe`（优先系统 PATH）。
  - 自动选择可用 SOCKS 端口（默认 1080，向上探测 20 个端口）。
  - 端口监听检测支持 `Get-NetTCPConnection` 与 `netstat` 回退。
  - 启动失败提供详细排查命令与日志路径。
- 优化 `gitlab-proxy/stop-proxy.ps1`
  - 无 PID 时，从 `~/.gitconfig-bgi-proxy-v3` 解析端口并按端口查杀进程。
  - 支持 `Get-NetTCPConnection` 与 `netstat` 回退查找 PID。
  - 输出明确的失败原因与排查命令。
- 优化 `gitlab-proxy/ssh/config`
  - `Host *` 禁用 `GSSAPIAuthentication`，加快 Windows 环境首包握手。
  - `Host win-*` 追加兼容性算法：`KexAlgorithms +diffie-hellman-group14-sha1`、`Ciphers +aes*-ctr`。
- 优化 `gitlab-proxy/gitconfig/.gitconfig`（Windows 专用）
  - `core.symlinks=false`、`core.fscache=true`、`core.protectNTFS=true`。
  - `feature.manyFiles=true`。

## 使用指引
- 启动代理：`gitlab-proxy/start-proxy.ps1`
  - 启动成功后，自动生成 `~/.gitconfig-bgi-proxy-v3`，只对 `https://git.bgi.com/` 生效。
- 停止代理：`gitlab-proxy/stop-proxy.ps1`
  - 无 PID 时会自动按端口扫描并尝试终止进程，同时清理代理配置文件。

## 常用排查命令
- 查看端口占用：`netstat -ano | findstr LISTENING | findstr :1080`
- 查看日志：`type %TEMP%\gitlab_proxy_log.txt`
- 手动调试 SSH：`ssh -vvv -N -D 127.0.0.1:1080 gitlab-proxy`
- 测试 SOCKS：`curl.exe --socks5-hostname 127.0.0.1:1080 https://git.bgi.com/ -v`
- 强制结束进程：`taskkill /PID <PID> /F`

## 兼容性与注意事项
- `ssh/config` 中 `gitlab-proxy` 需要可用的跳板机配置（例如 `dev10`）。
- 用户名 `shijiashuai`、主机 `10.227.5.229` 来自原配置，如需变更请同步调整。
- 若 `Get-NetTCPConnection` 不可用（旧版 PowerShell/Server Core），脚本将自动回退到 `netstat`。
