# 2025-10-21 SSH 管理脚本合并与简化

- **新增**: `Unix/ssh/ssh-manager.sh`
  - 模块划分：`server`（安装/启用/防火墙/追加公钥）、`client`（keygen/add-host/copy-id/connect）。
  - 默认策略：
    - 允许密码登录（`PasswordAuthentication yes`），同时开启公钥登录。
    - 默认密钥类型 `ed25519`（可选 `rsa`）。
    - `fzf` 支持交互式模糊选择；缺失时回退到简单选择。
  - 适配：优先使用 `systemd`，无 `systemd` 时回退 `service`/`init.d`；兼容 WSL2/容器/物理机常见场景。

- **合并复用**:
  - `client connect` 子命令复用原 `connect-ssh.sh` 的核心逻辑（读取 `~/.ssh/config`、fzf 选择、`--list`）。
  - `server enable` 子命令整合原 `enable-ssh-linux.sh` 的安装与服务启用、防火墙配置等能力，并简化为一条命令。

- **计划删除**（待执行命令后生效）:
  - `Unix/ssh/connect-ssh.sh`
  - `Unix/ssh/enable-ssh-linux.sh`

- **用法示例**:
  - 启用服务（服务器端）：
    - `./Unix/ssh/ssh-manager.sh server enable`
  - 生成密钥（客户端）：
    - `./Unix/ssh/ssh-manager.sh client keygen`
  - 添加主机并免密：
    - `./Unix/ssh/ssh-manager.sh client add-host --alias mybox --host 192.168.1.10 --user ubuntu`
    - `./Unix/ssh/ssh-manager.sh client copy-id --host mybox`
  - 交互式连接：
    - `./Unix/ssh/ssh-manager.sh client connect`

- **fzf 说明**:
  - fzf 是一个通用的命令行模糊查找器，在本项目中用于从 `~/.ssh/config` 的主机列表里快速筛选目标主机。
  - 安装（示例）：
    - Debian/Ubuntu: `sudo apt-get install -y fzf`
    - Fedora: `sudo dnf install -y fzf`
    - macOS (brew): `brew install fzf`
  - 若未安装 fzf，本脚本会回退到简单的交互选择或仅列出主机。
