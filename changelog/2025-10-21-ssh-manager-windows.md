# 2025-10-21 Windows SSH 客户端脚本新增

- **新增**: `Win/system/ssh-manager.ps1`
  - 子命令：
    - `client keygen`（默认 ed25519，支持 `--force`/`--comment`）
    - `client add-host`（向 `%USERPROFILE%/.ssh/config` 追加 Host 配置，支持 `--force`）
    - `client copy-id`（将公钥上传到远端并追加到 `~/.ssh/authorized_keys`）
    - `client connect`（交互式选择主机，支持 fzf.exe；缺失时回退）
  - 依赖：OpenSSH Client（ssh/ssh-keygen/scp），可选 `fzf.exe`。
  - 适用场景：从 Windows 客户端连接到远端 Linux/WSL2 主机。

- **注意（连接到远端 WSL2）**:
  - 在目标 WSL2 中需要安装并启用 OpenSSH Server（可用 `Unix/ssh/ssh-manager.sh server enable`）。
  - 需确保网络可达：
    - Windows 11/WSL 新版可启用 WSL2 Mirrored Networking，使 WSL2 获得可被局域网访问的地址；或
    - 在目标 Windows 上使用 `netsh interface portproxy` 将 22 端口转发到 WSL2 的内部地址。

- **用法示例**:
  - 生成密钥：`powershell -ExecutionPolicy Bypass -File .\Win\system\ssh-manager.ps1 client keygen`
  - 添加主机：`... client add-host --alias mywsl --host 192.168.1.50 --user ubuntu`
  - 上传公钥：`... client copy-id --host mywsl`
  - 连接：`... client connect`
