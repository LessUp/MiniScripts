#!/usr/bin/env bash
set -Eeuo pipefail

need_docker() {
  if ! command -v docker >/dev/null 2>&1; then
    echo "错误: 未找到 docker 命令" >&2
    exit 1
  fi
  if ! docker info >/dev/null 2>&1; then
    echo "错误: Docker 守护进程未运行或无权限" >&2
    exit 1
  fi
}

has_cmd() { command -v "$1" >/dev/null 2>&1; }

usage() {
  cat <<EOF
用法: $0 <命令> [子命令] [参数]

命令:
  images           镜像操作: list | save <镜像> <文件> | load <文件> | transfer <镜像> <user@host:/path>
  registry         本地镜像仓库: start | stop | push <镜像> | pull <镜像> | list
  migrate          容器迁移: export <容器> <文件.tar.gz> | import <文件.tar.gz> <新容器名>
  cleanup          资源清理: --containers | --images | --images-all | --volumes | --networks | --all [--force|--dry-run]
  logs             查看日志: [容器名或ID] [--follow]
  status           状态概览
  diag             诊断: check-daemon | check-container <容器> | check-network [容器] | check-storage | check-permissions | full-check

示例:
  $0 images list
  $0 images save nginx:latest /tmp/nginx.tar
  $0 registry start
  $0 migrate export myctr /tmp/myctr.tgz
  $0 cleanup --all --dry-run
  $0 logs myctr --follow
  $0 status
  $0 diag full-check
EOF
}

images_cmd() {
  need_docker
  local sub=${1:-}
  case "$sub" in
    list)
      echo "===== 本地镜像 ====="
      docker images --format "table {{.Repository}}:{{.Tag}}\t{{.ID}}\t{{.Size}}\t{{.CreatedAt}}"
      echo
      echo "数量: $(docker images -q | wc -l)"
      echo "磁盘占用: $(docker system df | awk '/Images/ {print $4}')"
      ;;
    save)
      local image=${2:-} out=${3:-}
      [ -n "$image" ] && [ -n "$out" ] || { echo "用法: $0 images save <镜像> <文件>"; exit 1; }
      if ! docker images --format '{{.Repository}}:{{.Tag}}' | grep -qx "$image"; then
        echo "错误: 镜像不存在: $image"; exit 1
      fi
      echo "保存镜像: $image -> $out"
      docker save -o "$out" "$image"
      ;;
    load)
      local file=${2:-}
      [ -n "$file" ] || { echo "用法: $0 images load <文件>"; exit 1; }
      [ -f "$file" ] || { echo "错误: 文件不存在: $file"; exit 1; }
      echo "加载镜像: $file"
      docker load -i "$file"
      ;;
    transfer)
      local image=${2:-} dest=${3:-}
      [ -n "$image" ] && [ -n "$dest" ] || { echo "用法: $0 images transfer <镜像> <user@host:/path>"; exit 1; }
      if ! echo "$dest" | grep -q ".*@.*:.*"; then
        echo "错误: 目标格式应为 user@host:/path"; exit 1
      fi
      if ! docker images --format '{{.Repository}}:{{.Tag}}' | grep -qx "$image"; then
        echo "错误: 镜像不存在: $image"; exit 1
      fi
      local tmp="/tmp/docker-image-$(date +%s).tar"
      echo "保存临时文件: $tmp"
      docker save -o "$tmp" "$image"
      echo "传输至: $dest"
      scp "$tmp" "$dest"
      rm -f "$tmp" || true
      echo "在远端加载: docker load -i <文件>"
      ;;
    *)
      echo "未知子命令: images $sub"; usage; exit 1;;
  esac
}

registry_cmd() {
  need_docker
  local sub=${1:-}
  case "$sub" in
    start)
      if docker ps --format '{{.Image}} {{.Names}}' | grep -q '^registry:2 '; then
        echo "本地仓库已在运行"
      else
        docker run -d -p 5000:5000 --restart=always --name registry registry:2
        echo "已启动: localhost:5000"
      fi
      ;;
    stop)
      docker rm -f registry 2>/dev/null || true
      echo "已停止并删除 registry"
      ;;
    push)
      local image=${2:-}
      [ -n "$image" ] || { echo "用法: $0 registry push <镜像>"; exit 1; }
      local repo=${image%%:*}
      local tag=${image##*:}
      local regimg="localhost:5000/${repo}:${tag}"
      docker tag "$image" "$regimg"
      docker push "$regimg"
      ;;
    pull)
      local image=${2:-}
      [ -n "$image" ] || { echo "用法: $0 registry pull <镜像>"; exit 1; }
      docker pull "localhost:5000/$image"
      ;;
    list)
      if has_cmd curl; then
        curl -s http://localhost:5000/v2/_catalog || echo "无法访问 http://localhost:5000"
      else
        echo "缺少 curl，无法列出仓库目录"
      fi
      ;;
    *)
      echo "未知子命令: registry $sub"; usage; exit 1;;
  esac
}

migrate_cmd() {
  need_docker
  local sub=${1:-}
  case "$sub" in
    export)
      local ctr=${2:-} out=${3:-}
      [ -n "$ctr" ] && [ -n "$out" ] || { echo "用法: $0 migrate export <容器> <文件.tar.gz>"; exit 1; }
      if ! docker ps -a --format '{{.Names}}' | grep -qx "$ctr"; then
        echo "错误: 容器不存在: $ctr"; exit 1
      fi
      local tmp="/tmp/docker_migrate_$(date +%s)"
      mkdir -p "$tmp"
      local image="migrate/${ctr}:$(date +%s)"
      docker commit "$ctr" "$image"
      docker save -o "$tmp/image.tar" "$image"
      docker inspect "$ctr" > "$tmp/metadata.json"
      tar -czf "$out" -C "$tmp" .
      docker rmi "$image" >/dev/null 2>&1 || true
      rm -rf "$tmp"
      echo "已导出到: $out"
      ;;
    import)
      local file=${2:-} newname=${3:-}
      [ -n "$file" ] && [ -n "$newname" ] || { echo "用法: $0 migrate import <文件.tar.gz> <新容器名>"; exit 1; }
      [ -f "$file" ] || { echo "错误: 文件不存在: $file"; exit 1; }
      local tmp="/tmp/docker_migrate_$(date +%s)"
      mkdir -p "$tmp"
      tar -xzf "$file" -C "$tmp"
      local out
      out=$(docker load -i "$tmp/image.tar")
      local image
      image=$(echo "$out" | awk -F': ' '/Loaded image/ {print $2}' | tail -n1)
      [ -n "$image" ] || image=$(docker images --format '{{.Repository}}:{{.Tag}}' | head -n1)
      local cmd="" entry=""
      if has_cmd jq && [ -f "$tmp/metadata.json" ]; then
        cmd=$(jq -r '.Config.Cmd // [] | join(" ")' "$tmp/metadata.json")
        entry=$(jq -r '.Config.Entrypoint // [] | join(" ")' "$tmp/metadata.json")
      fi
      docker create --name "$newname" $entry $cmd "$image"
      rm -rf "$tmp"
      echo "已创建容器: $newname"
      ;;
    *)
      echo "未知子命令: migrate $sub"; usage; exit 1;;
  esac
}

cleanup_cmd() {
  need_docker
  local CLEAN_CONTAINERS=false
  local CLEAN_IMAGES=false
  local CLEAN_IMAGES_ALL=false
  local CLEAN_VOLUMES=false
  local CLEAN_NETWORKS=false
  local FORCE=false
  local DRY_RUN=true

  while [ $# -gt 0 ]; do
    case "$1" in
      --containers) CLEAN_CONTAINERS=true ;;
      --images) CLEAN_IMAGES=true ;;
      --images-all) CLEAN_IMAGES_ALL=true ;;
      --volumes) CLEAN_VOLUMES=true ;;
      --networks) CLEAN_NETWORKS=true ;;
      --all) CLEAN_CONTAINERS=true; CLEAN_IMAGES=true; CLEAN_VOLUMES=true; CLEAN_NETWORKS=true ;;
      --force) FORCE=true; DRY_RUN=false ;;
      --dry-run) DRY_RUN=true; FORCE=false ;;
      -h|--help) echo "用法: $0 cleanup [目标] [--force|--dry-run]"; return 0 ;;
      *) echo "未知选项: $1"; return 1 ;;
    esac
    shift
  done

  if ! $CLEAN_CONTAINERS && ! $CLEAN_IMAGES && ! $CLEAN_IMAGES_ALL && ! $CLEAN_VOLUMES && ! $CLEAN_NETWORKS; then
    echo "错误: 请至少指定一个清理目标"; return 1
  fi

  list_items() { echo "将要清理的 $1:"; eval "$2" || true; echo; }

  if $CLEAN_CONTAINERS; then
    if $DRY_RUN; then
      list_items "已停止容器" "docker ps -a --filter status=exited --format '{{.ID}}\t{{.Names}}'"
    else
      docker container prune -f
    fi
  fi

  if $CLEAN_IMAGES_ALL; then
    if $DRY_RUN; then
      list_items "所有未使用镜像" "docker image ls -a --format '{{.Repository}}:{{.Tag}} {{.ID}}' | grep -v -E ':[^ ]+' || true"
    else
      docker image prune -a -f
    fi
  elif $CLEAN_IMAGES; then
    if $DRY_RUN; then
      list_items "悬空镜像" "docker images -f dangling=true --format '{{.ID}}\t{{.Repository}}:{{.Tag}}'"
    else
      docker image prune -f
    fi
  fi

  if $CLEAN_VOLUMES; then
    if $DRY_RUN; then
      list_items "未使用卷" "docker volume ls -f dangling=true --format '{{.Name}}'"
    else
      docker volume prune -f
    fi
  fi

  if $CLEAN_NETWORKS; then
    if $DRY_RUN; then
      list_items "未使用网络" "docker network ls -f dangling=true --format '{{.ID}}\t{{.Name}}'"
    else
      docker network prune -f
    fi
  fi

  if $FORCE; then
    docker system df
  fi
}

logs_cmd() {
  need_docker
  local ctr=""; local follow=false
  while [ $# -gt 0 ]; do
    case "$1" in
      --follow) follow=true ;;
      *) ctr="$1" ;;
    esac
    shift || true
  done

  if [ -z "$ctr" ]; then
    mapfile -t RUNNING < <(docker ps --format '{{.ID}} {{.Names}}') || true
    if [ ${#RUNNING[@]} -eq 0 ]; then echo "没有运行中的容器"; return 0; fi
    echo "选择要查看日志的容器:"; local i=0; local idx=1
    while [ $i -lt ${#RUNNING[@]} ]; do
      echo "$idx) ${RUNNING[$((i+1))]}"; i=$((i+2)); idx=$((idx+1))
    done
    read -r -p "输入序号: " sel
    if ! [[ "$sel" =~ ^[0-9]+$ ]] || [ "$sel" -lt 1 ] || [ "$sel" -gt $(( ${#RUNNING[@]} / 2 )) ]; then
      echo "无效选择"; return 1
    fi
    ctr=${RUNNING[$((sel*2-2))]}
  fi
  if $follow; then docker logs -f "$ctr"; else docker logs "$ctr"; fi
}

status_cmd() {
  need_docker
  echo "===== Docker 信息 ====="; docker info --format '{{json .}}' 2>/dev/null | jq -r '.ServerVersion? as $v | "ServerVersion: \($v)"' 2>/dev/null || docker info | sed -n '1,15p'
  echo
  echo "===== 资源占用 ====="; docker system df
  echo
  echo "===== 运行容器 (前10) ====="; docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}' | sed -n '1,11p'
}

diag_cmd() {
  need_docker
  local sub=${1:-}; shift || true
  case "$sub" in
    check-daemon)
      if has_cmd systemctl; then
        if systemctl is-active --quiet docker; then echo "[OK] docker 运行中"; else echo "[FAIL] docker 未运行"; fi
        has_cmd journalctl && journalctl -u docker.service -n 20 --no-pager || true
      else
        echo "systemctl 不可用，跳过服务状态。尝试 docker info..."; docker info >/dev/null && echo "[OK] docker 可用" || echo "[FAIL] docker 不可用"
      fi
      ;;
    check-container)
      local ctr=${1:-}; [ -n "$ctr" ] || { echo "用法: $0 diag check-container <容器>"; exit 1; }
      if ! docker ps -a --format '{{.Names}}' | grep -qx "$ctr"; then echo "容器不存在: $ctr"; exit 1; fi
      docker ps -a -f "name=$ctr"; echo; docker inspect -f '状态={{.State.Status}} 重启={{.RestartCount}}' "$ctr"; echo; docker logs --tail 50 "$ctr" || true; echo; docker stats --no-stream "$ctr" || true
      ;;
    check-network)
      local ctr=${1:-}
      if [ -n "$ctr" ]; then
        if ! docker ps -a --format '{{.Names}}' | grep -qx "$ctr"; then echo "容器不存在: $ctr"; exit 1; fi
        echo "测试外网连接 (8.8.8.8)"; docker exec "$ctr" sh -c 'ping -c 3 8.8.8.8 || ping -n 3 8.8.8.8' || true
        echo "测试 DNS 解析 (google.com)"; docker exec "$ctr" sh -c 'ping -c 3 google.com || ping -n 3 google.com' || true
      else
        echo "/etc/resolv.conf:"; cat /etc/resolv.conf || true
        if has_cmd ufw; then ufw status || true; fi
      fi
      ;;
    check-storage)
      docker system df; echo; docker system df -v || true
      ;;
    check-permissions)
      if id -nG "$USER" 2>/dev/null | grep -qw docker; then echo "[OK] $USER 属于 docker 组"; else echo "[WARN] $USER 不在 docker 组"; fi
      ;;
    full-check)
      "$0" diag check-daemon || true; echo; "$0" diag check-permissions || true; echo; "$0" diag check-storage || true; echo; echo "===== 容器概览 ====="; docker ps -a
      ;;
    *) echo "未知子命令: diag $sub"; usage; exit 1;;
  esac
}

main() {
  local cmd=${1:-}
  case "$cmd" in
    images) shift || true; images_cmd "$@" ;;
    registry) shift || true; registry_cmd "$@" ;;
    migrate) shift || true; migrate_cmd "$@" ;;
    cleanup) shift || true; cleanup_cmd "$@" ;;
    logs) shift || true; logs_cmd "$@" ;;
    status) status_cmd ;;
    diag) shift || true; diag_cmd "$@" ;;
    -h|--help|help|"") usage ;;
    *) echo "未知命令: $cmd"; usage; exit 1 ;;
  esac
}

main "$@"

