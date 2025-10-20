# GitLab 代理统一解决方案 (v4.0)

## 核心优势

- **一键启停，精确控制**：专为公司内网设计，一个命令启动代理，通过 Git `includeIf` 指令精确控制代理范围。
- **非侵入式**：代理配置仅对公司 GitLab 项目生效，不污染全局 `http.proxy`，不影响 GitHub 等其他项目。
- **跨平台兼容**：核心 `ssh_config` 跨平台通用，脚本分别适配 Windows 和 macOS/Linux。

## 原理简介

本方案通过三个组件协同工作：
1.  **`hosts` 文件（可选）**：用于浏览器访问或在某些不支持“通过代理解析 DNS”的客户端中辅助解析内网域名。Git 侧采用 `socks5h`，通常无需修改 `hosts`。
2.  **Git `includeIf` 配置**：在您的全局 `.gitconfig` 中设置一条条件规则，告知 Git："仅在处理 `git.bgi.com` 相关项目时，才加载一个名为 `.gitconfig-bgi-proxy-v3` 的特定代理配置"。
3.  **代理脚本 (`start/stop-proxy`)**：`start` 启动 SSH SOCKS5 代理隧道，并**创建** `~/.gitconfig-bgi-proxy-v3`；`stop` 关闭隧道并**删除**该文件。脚本不再修改全局 `include.path`。

---

## 一次性环境设置

首次使用前，请确保完成以下四步设置。

### 步骤一：配置 `hosts` 文件（可选，需管理员权限）

1.  用**管理员身份**打开文本编辑器（如记事本、VS Code）。
2.  打开文件 `C:\Windows\System32\drivers\etc\hosts` (macOS/Linux: `/etc/hosts`)。
3.  在文件末尾添加以下一行并保存：
    ```
    10.17.1.2    git.bgi.com
    ```
    *(注: `10.17.1.2` 是 `git.bgi.com` 的内网 IP 地址。若 Git 走 `socks5h`，此步骤可省略；浏览器可按需设置)*

### 步骤二：配置 SSH `config` 文件

这部分定义了如何连接服务器及启动代理。

1.  将本项目 `gitlab/ssh/config` 文件中的 **全部内容** 复制到你的 SSH 配置文件中。
    -   **路径**: `~/.ssh/config` (Windows: `C:\Users\你的用户名\.ssh\config`)
    -   如果 `config` 文件已存在，请将内容合并。该配置是独立的，通常不会产生冲突。

### 步骤三：配置 Git 全局 `includeIf`

这是实现代理精确控制的核心。

1.  **检查并清理旧配置**：确保您的全局 `.gitconfig` (`C:\Users\你的用户名\.gitconfig`) 中**没有**任何 `[http]` 或 `[https]` 下的 `proxy = ...` 全局设置。
2.  **添加 `includeIf` 指令**：打开该文件，在末尾添加以下内容并保存：
    ```ini
    # --- 公司项目代理自动切换 ---
    [includeIf "hasconfig:remote.*.url:https://git.bgi.com/"]
        path = .gitconfig-bgi-proxy-v3
    ```
    *(Git 会在您的 HOME 目录下查找由脚本生成的 `.gitconfig-bgi-proxy-v3` 文件)*

### 步骤四：配置 Git 凭据管理器 (推荐)

为了消除在 `git clone` 或 `pull` 时可能出现的 `ServicePointManager` 警告，推荐执行以下命令。

此警告来自于 Git 凭据管理器 (GCM)，它尝试连接服务器但不支持 SOCKS5 代理。以下命令可以让 GCM 跳过这个检查，从而消除警告。

在 **PowerShell** 或 **Git Bash** 中运行:
```bash
git config --global credential.https://git.bgi.com.useHttpPath true
```

---

## 日常使用

完成一次性设置后，日常操作非常简单。

### 启动代理

在公司网络内，当需要访问公司 GitLab 时：
- **Windows**:
  ```powershell
  # 打开 PowerShell, 切换到 GitlabProxy/v3 目录
  cd GitlabProxy/v3
  .\start-proxy.ps1
  ```
- **macOS / Linux**:
  ```bash
  # 打开终端, 切换到 GitlabProxy/v3 目录
  cd GitlabProxy/v3
  ./start-proxy.sh
  ```
脚本会自动启动 SSH 代理隧道，并为 Git 命令配置好代理。端口固定为 `127.0.0.1:1080`（可通过环境变量 `GITLAB_SOCKS_PORT` 临时覆盖）。

**注意**
- **端口冲突处理**：采用固定端口策略，若 1080 被占用脚本会直接报错并提示占用者，便于排查。
- **转发策略**：脚本通过命令行参数 `-D 127.0.0.1:1080` 注入动态转发，请避免在 `~/.ssh/config` 中为 `Host gitlab-proxy` 静态配置 `DynamicForward` 以免叠加。
- **配置建议**：请不要在 `~/.ssh/config` 的 `Host gitlab-proxy` 中静态配置 `DynamicForward`，转发由脚本注入，端口固定 1080。

### 浏览器访问

当代理启动后，您可以配置您的浏览器来访问公司内网网站（如 GitLab 网页版）。

1.  打开浏览器的代理设置。
2.  选择 **手动代理配置**。
3.  在 **SOCKS 主机** (SOCKS Host) 字段中，输入 `127.0.0.1`。
4.  在 **端口** (Port) 字段中，输入 `1080`。
5.  确保选择 **SOCKS v5**。
6.  保存设置。

**说明**: 我们在 Git 配置中指定使用 `socks5h://`，由代理服务器解析公司内网域名，避免本地 `hosts` 依赖。默认 SSH 目标为 `gitlab-proxy`（见 `ssh/config`）。
-   **Git 命令**：使用 `socks5h://127.0.0.1:1080`，保证 `git.bgi.com` 等内网域名解析正确。
-   **浏览器**：配置 SOCKS v5 代理，并启用“通过代理解析 DNS”（不同浏览器项名称可能不同）；如无法启用，可按需添加 `hosts`。

提示：脚本会在 `$HOME/.gitconfig-bgi-proxy-v3` 中写入 `socks5h://127.0.0.1:1080`，Git 将按该文件生效（固定端口）。

因此，本方案兼顾 Git 客户端与浏览器：Git 通过 `socks5h` 自动解析内网域名，浏览器按需启用远程 DNS 或使用 `hosts` 辅助。

### 停止代理

用完后，在相同目录下执行：
- **Windows**: `.\stop-proxy.ps1`
- **macOS / Linux**: `./stop-proxy.sh`

脚本会自动关闭 SSH 进程并清理所有 Git 代理配置。

---

### SSH 协议使用 (`git@git.bgi.com`)

**无需任何额外操作！**

如果你使用 SSH 协议 (`git clone git@...`)，`ssh_config` 文件已配置 `dev10` 作为跳转主机，只要在公司内网即可无缝使用，无需启动任何代理脚本。
