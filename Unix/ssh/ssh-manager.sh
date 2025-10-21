#!/usr/bin/env bash
set -euo pipefail

CONFIG_FILE="${HOME}/.ssh/config"
DEFAULT_PORT=22

usage() {
  cat <<EOF
用法: $0 <server|client> <子命令> [选项]

子命令:
  server enable                  安装并启用 SSH 服务，默认允许密码登录
  server add-pubkey [选项]      向指定用户追加公钥
      --user <USER>             目标用户，默认当前用户
      --pubkey <PATH>           公钥文件，默认 ~/.ssh/id_ed25519.pub

  client keygen [选项]          生成 SSH 密钥（默认 ed25519）
      --type <ed25519|rsa>      默认 ed25519
      --force                   已存在时覆盖
      --comment <STR>           密钥注释，默认 "$(whoami)@$(hostname)"

  client add-host [选项]        追加主机配置到 ~/.ssh/config
      --alias <NAME>            主机别名（必填）
      --host <IP/DOMAIN>        主机名或 IP（必填）
      --user <USER>             登录用户（必填）
      --port <PORT>             默认 22
      --identity-file <PATH>    私钥文件路径，默认 ~/.ssh/id_ed25519
      --force                   已存在同名 Host 时覆盖

  client copy-id [选项]         将本地公钥复制到远端（免密）
      --host <ALIAS|user@ip>    目标（别名或 user@host）（必填）
      --key <PATH>              公钥路径，默认 ~/.ssh/id_ed25519.pub

  client connect [选项]         交互式选择主机并连接
      -c, --config <PATH>       SSH 配置文件，默认 ~/.ssh/config
      -l, --list                仅列出主机，不连接

示例:
  $0 server enable
  $0 client keygen
  $0 client add-host --alias mybox --host 192.168.1.10 --user ubuntu
  $0 client copy-id --host mybox
  $0 client connect
EOF
}

pm_detect() {
  if command -v apt-get >/dev/null 2>&1; then echo apt; return; fi
  if command -v dnf >/dev/null 2>&1; then echo dnf; return; fi
  if command -v yum >/dev/null 2>&1; then echo yum; return; fi
  echo none
}

pkg_install_openssh_server() {
  local pm; pm=$(pm_detect)
  case "$pm" in
    apt)
      if command -v dpkg >/dev/null 2>&1 && dpkg -s openssh-server >/dev/null 2>&1; then return 0; fi
      sudo apt-get update -y
      sudo DEBIAN_FRONTEND=noninteractive apt-get install -y openssh-server
      ;;
    dnf)
      if command -v rpm >/dev/null 2>&1 && rpm -q openssh-server >/dev/null 2>&1; then return 0; fi
      sudo dnf install -y openssh-server
      ;;
    yum)
      if command -v rpm >/dev/null 2>&1 && rpm -q openssh-server >/dev/null 2>&1; then return 0; fi
      sudo yum install -y openssh-server
      ;;
    *)
      echo "未检测到受支持的包管理器(apt/dnf/yum)，请手动安装 openssh-server" >&2
      return 1
      ;;
  esac
}

edit_sshd_config_auth() {
  local cfg="/etc/ssh/sshd_config"
  if ! sudo test -f "$cfg"; then
    echo "找不到 $cfg" >&2
    return 1
  fi
  if sudo grep -Eq '^\s*PasswordAuthentication' "$cfg"; then
    sudo sed -i -E 's/^\s*#?\s*PasswordAuthentication\s+.*/PasswordAuthentication yes/' "$cfg"
  else
    echo "PasswordAuthentication yes" | sudo tee -a "$cfg" >/dev/null
  fi
  if sudo grep -Eq '^\s*PubkeyAuthentication' "$cfg"; then
    sudo sed -i -E 's/^\s*#?\s*PubkeyAuthentication\s+.*/PubkeyAuthentication yes/' "$cfg"
  else
    echo "PubkeyAuthentication yes" | sudo tee -a "$cfg" >/dev/null
  fi
}

service_name_detect() {
  if command -v systemctl >/dev/null 2>&1; then
    if systemctl list-unit-files | grep -q '^sshd.service'; then echo sshd; return; fi
    if systemctl list-unit-files | grep -q '^ssh.service'; then echo ssh; return; fi
  fi
  # 非 systemd 发行版
  if [ -x "/etc/init.d/ssh" ]; then echo ssh; return; fi
  if command -v service >/dev/null 2>&1 && service --status-all 2>&1 | grep -q sshd; then echo sshd; return; fi
  echo sshd
}

server_enable() {
  pkg_install_openssh_server
  edit_sshd_config_auth

  local svc; svc=$(service_name_detect)
  if command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ]; then
    sudo systemctl enable "$svc" || true
    sudo systemctl restart "$svc" || sudo systemctl start "$svc" || true
    sudo systemctl is-active --quiet "$svc" || echo "警告: 服务 $svc 未处于活动状态" >&2
  else
    if command -v service >/dev/null 2>&1; then
      sudo service "$svc" restart || sudo service "$svc" start || true
    elif [ -x "/etc/init.d/$svc" ]; then
      sudo "/etc/init.d/$svc" restart || sudo "/etc/init.d/$svc" start || true
    else
      echo "未找到可用的服务管理器。可尝试手动运行: sudo /usr/sbin/sshd -D" >&2
    fi
  fi

  if command -v ufw >/dev/null 2>&1; then
    if ! sudo ufw status | grep -qw inactive; then
      sudo ufw allow ssh || sudo ufw allow ${DEFAULT_PORT}/tcp || true
    fi
  elif command -v firewall-cmd >/dev/null 2>&1; then
    if sudo firewall-cmd --state >/dev/null 2>&1; then
      sudo firewall-cmd --permanent --add-service=ssh || sudo firewall-cmd --permanent --add-port=${DEFAULT_PORT}/tcp || true
      sudo firewall-cmd --reload || true
    fi
  fi
  echo "SSH 服务已启用（允许密码登录、允许公钥登录）。"
}

server_add_pubkey() {
  local target_user="${1:-}"
  local pubkey_path="${2:-}"
  if [ -z "$target_user" ]; then target_user="$(whoami)"; fi
  if [ -z "$pubkey_path" ]; then pubkey_path="${HOME}/.ssh/id_ed25519.pub"; fi
  if [ ! -f "$pubkey_path" ]; then echo "公钥不存在: $pubkey_path" >&2; exit 1; fi
  local user_home
  user_home=$(eval echo ~"$target_user")
  sudo mkdir -p "$user_home/.ssh"
  sudo touch "$user_home/.ssh/authorized_keys"
  cat "$pubkey_path" | sudo tee -a "$user_home/.ssh/authorized_keys" >/dev/null
  sudo chown -R "$target_user":"$target_user" "$user_home/.ssh"
  sudo chmod 700 "$user_home/.ssh"
  sudo chmod 600 "$user_home/.ssh/authorized_keys"
  echo "已向用户 $target_user 追加公钥。"
}

client_keygen() {
  local type="ed25519" force=false comment
  comment="$(whoami)@$(hostname)"
  while [ $# -gt 0 ]; do
    case "$1" in
      --type) type="$2"; shift 2;;
      --force) force=true; shift;;
      --comment) comment="$2"; shift 2;;
      *) echo "未知选项: $1" >&2; exit 1;;
    esac
  done
  mkdir -p "$HOME/.ssh"
  local keyfile
  if [ "$type" = "rsa" ]; then keyfile="$HOME/.ssh/id_rsa"; else keyfile="$HOME/.ssh/id_ed25519"; fi
  if [ -f "$keyfile" ] && [ "$force" != true ]; then
    echo "密钥已存在: $keyfile（使用 --force 覆盖）"; return 0
  fi
  if [ "$type" = "rsa" ]; then
    ssh-keygen -t rsa -b 4096 -N "" -C "$comment" -f "$keyfile"
  else
    ssh-keygen -t ed25519 -N "" -C "$comment" -f "$keyfile"
  fi
  chmod 700 "$HOME/.ssh" || true
  chmod 600 "$keyfile" || true
  echo "密钥生成完成: $keyfile"
}

client_add_host() {
  local alias="" host="" user="" port="$DEFAULT_PORT" identity="$HOME/.ssh/id_ed25519" force=false
  while [ $# -gt 0 ]; do
    case "$1" in
      --alias) alias="$2"; shift 2;;
      --host) host="$2"; shift 2;;
      --user) user="$2"; shift 2;;
      --port) port="$2"; shift 2;;
      --identity-file) identity="$2"; shift 2;;
      --force) force=true; shift;;
      *) echo "未知选项: $1" >&2; exit 1;;
    esac
  done
  if [ -z "$alias" ] || [ -z "$host" ] || [ -z "$user" ]; then
    echo "--alias/--host/--user 为必填项" >&2; exit 1
  fi
  mkdir -p "$HOME/.ssh"; touch "$CONFIG_FILE"; chmod 600 "$CONFIG_FILE" || true
  if grep -Eq "^Host\s+$alias(\s|$)" "$CONFIG_FILE"; then
    if [ "$force" != true ]; then
      echo "Host $alias 已存在（使用 --force 覆盖）" >&2; exit 1
    else
      awk -v alias="$alias" 'BEGIN{rm=0} {
        if ($1=="Host" && $2==alias){rm=1; next}
        if (rm==1 && $1=="Host"){rm=0}
        if (rm==0) print $0
      } END{if(rm==1){} }' "$CONFIG_FILE" >"$CONFIG_FILE.tmp"
      mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
    fi
  fi
  {
    echo "Host $alias"
    echo "  HostName $host"
    echo "  User $user"
    echo "  Port $port"
    echo "  IdentityFile $identity"
    echo "  ServerAliveInterval 60"
    echo "  ServerAliveCountMax 3"
  } >> "$CONFIG_FILE"
  echo "已追加 Host $alias 到 $CONFIG_FILE"
}

client_copy_id() {
  local target="" key="$HOME/.ssh/id_ed25519.pub"
  while [ $# -gt 0 ]; do
    case "$1" in
      --host) target="$2"; shift 2;;
      --key) key="$2"; shift 2;;
      *) echo "未知选项: $1" >&2; exit 1;;
    esac
  done
  if [ -z "$target" ]; then echo "--host 为必填项" >&2; exit 1; fi
  if [ ! -f "$key" ]; then echo "公钥不存在: $key" >&2; exit 1; fi
  ssh-copy-id -i "$key" "$target"
}

client_connect() {
  local cfg="$CONFIG_FILE" list_only=false
  while [ $# -gt 0 ]; do
    case "$1" in
      -c|--config) cfg="$2"; shift 2;;
      -l|--list) list_only=true; shift;;
      *) echo "未知选项: $1" >&2; exit 1;;
    esac
  done
  if [ ! -f "$cfg" ]; then echo "配置文件未找到: $cfg" >&2; exit 1; fi
  local hosts; hosts=$(grep -E '^Host ' "$cfg" | awk '{print $2}' | grep -v '\*' || true)
  if [ -z "$hosts" ]; then echo "在 $cfg 中没有找到任何有效的主机定义"; exit 1; fi
  if [ "$list_only" = true ]; then echo "$hosts"; return 0; fi
  local selected
  if command -v fzf >/dev/null 2>&1; then
    selected=$(echo "$hosts" | fzf --height 40% --reverse --prompt="请选择要连接的主机: ")
  else
    echo "未检测到 fzf，将使用简单选择。"
    select h in $hosts; do selected="$h"; break; done
  fi
  if [ -n "${selected:-}" ]; then
    echo "正在连接: $selected"
    exec ssh "$selected"
  else
    echo "未选择任何主机"
  fi
}

main() {
  if [ $# -lt 1 ]; then usage; exit 1; fi
  case "$1" in
    server)
      shift
      case "${1:-}" in
        enable)
          shift || true
          server_enable "$@"
          ;;
        add-pubkey)
          shift || true
          local user="" pubkey=""
          while [ $# -gt 0 ]; do
            case "$1" in
              --user) user="$2"; shift 2;;
              --pubkey) pubkey="$2"; shift 2;;
              *) echo "未知选项: $1" >&2; exit 1;;
            esac
          done
          server_add_pubkey "$user" "$pubkey"
          ;;
        *) usage; exit 1;;
      esac
      ;;
    client)
      shift
      case "${1:-}" in
        keygen)
          shift || true
          client_keygen "$@"
          ;;
        add-host)
          shift || true
          client_add_host "$@"
          ;;
        copy-id)
          shift || true
          client_copy_id "$@"
          ;;
        connect)
          shift || true
          client_connect "$@"
          ;;
        *) usage; exit 1;;
      esac
      ;;
    -h|--help|help)
      usage
      ;;
    *) usage; exit 1;;
  esac
}

main "$@"
