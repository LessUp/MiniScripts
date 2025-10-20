#!/bin/bash
# Ubuntu备份与恢复工具
# 用法: 
# 备份: ./06-backup-restore.sh backup <源目录> <目标目录>
# 恢复: ./06-backup-restore.sh restore <备份文件> <目标目录>

# 显示帮助信息
show_help() {
  echo "Ubuntu备份与恢复工具"
  echo "用法: "
  echo "  备份: $0 backup <源目录> <目标目录>"
  echo "  恢复: $0 restore <备份文件> <目标目录>"
  echo "例如: "
  echo "  $0 backup /home/user/project /mnt/backup"
  echo "  $0 restore /mnt/backup/project_20250624.tar.gz /home/user/restore"
}

# 检查参数
if [ $# -lt 3 ]; then
  show_help
  exit 1
fi

ACTION="$1"
SOURCE="$2"
TARGET="$3"
DATE=$(date +%Y%m%d)

# 备份功能
do_backup() {
  if [ ! -d "$SOURCE" ]; then
    echo "错误: 源目录不存在!"
    exit 1
  fi
  
  if [ ! -d "$TARGET" ]; then
    echo "错误: 目标目录不存在!"
    exit 1
  }
  
  # 获取源目录名称
  SOURCE_NAME=$(basename "$SOURCE")
  BACKUP_FILE="${TARGET}/${SOURCE_NAME}_${DATE}.tar.gz"
  
  echo "===== Ubuntu备份工具 ====="
  echo "开始备份: $SOURCE"
  echo "备份到: $BACKUP_FILE"
  
  # 创建备份
  tar -czf "$BACKUP_FILE" -C "$(dirname "$SOURCE")" "$SOURCE_NAME"
  
  # 检查备份是否成功
  if [ $? -eq 0 ]; then
    echo "备份成功完成!"
    echo "备份文件: $BACKUP_FILE"
    echo "备份大小: $(du -h "$BACKUP_FILE" | cut -f1)"
  else
    echo "备份失败!"
  fi
}

# 恢复功能
do_restore() {
  if [ ! -f "$SOURCE" ]; then
    echo "错误: 备份文件不存在!"
    exit 1
  }
  
  if [ ! -d "$TARGET" ]; then
    echo "目标目录不存在，正在创建..."
    mkdir -p "$TARGET"
  }
  
  echo "===== Ubuntu恢复工具 ====="
  echo "开始恢复: $SOURCE"
  echo "恢复到: $TARGET"
  
  # 解压备份
  tar -xzf "$SOURCE" -C "$TARGET"
  
  # 检查恢复是否成功
  if [ $? -eq 0 ]; then
    echo "恢复成功完成!"
    echo "文件已恢复到: $TARGET"
  else
    echo "恢复失败!"
  fi
}

# 根据参数执行相应操作
case "$ACTION" in
  "backup")
    do_backup
    ;;
  "restore")
    do_restore
    ;;
  *)
    echo "未知的操作: $ACTION"
    show_help
    exit 1
    ;;
esac
