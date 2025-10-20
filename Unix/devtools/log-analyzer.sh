#!/bin/bash
# Ubuntu日志分析工具
# 用法: ./09-log-analyzer.sh [日志文件路径] [选项]
# 选项: errors, warnings, all

# 显示帮助信息
show_help() {
  echo "Ubuntu日志分析工具"
  echo "用法: $0 [日志文件路径] [选项]"
  echo "选项:"
  echo "  errors   - 只显示错误信息"
  echo "  warnings - 只显示警告信息"
  echo "  all      - 显示所有日志信息（默认）"
  echo "例如: $0 /var/log/syslog errors"
}

# 默认日志文件
DEFAULT_LOG="/var/log/syslog"
# 默认选项
DEFAULT_OPTION="all"

# 解析参数
LOG_FILE="${1:-$DEFAULT_LOG}"
OPTION="${2:-$DEFAULT_OPTION}"

# 检查日志文件是否存在
if [ ! -f "$LOG_FILE" ]; then
  echo "错误: 日志文件不存在: $LOG_FILE"
  echo "请检查路径是否正确，或者尝试以下常用日志文件:"
  echo "  /var/log/syslog"
  echo "  /var/log/auth.log"
  echo "  /var/log/kern.log"
  echo "  /var/log/apache2/access.log"
  echo "  /var/log/nginx/access.log"
  exit 1
fi

# 分析日志文件
analyze_log() {
  echo "===== 日志分析工具 ====="
  echo "分析文件: $LOG_FILE"
  echo "分析模式: $OPTION"
  
  echo -e "\n文件统计信息:"
  echo "文件大小: $(du -h "$LOG_FILE" | cut -f1)"
  echo "总行数: $(wc -l < "$LOG_FILE")"
  
  # 根据选项分析日志
  case "$OPTION" in
    "errors")
      echo -e "\n找到的错误信息:"
      grep -i "error\|fail\|critical\|emerg" "$LOG_FILE" | tail -n 30
      
      echo -e "\n错误统计:"
      echo "错误总数: $(grep -i "error\|fail\|critical\|emerg" "$LOG_FILE" | wc -l)"
      ;;
      
    "warnings")
      echo -e "\n找到的警告信息:"
      grep -i "warn\|warning\|notice" "$LOG_FILE" | tail -n 30
      
      echo -e "\n警告统计:"
      echo "警告总数: $(grep -i "warn\|warning\|notice" "$LOG_FILE" | wc -l)"
      ;;
      
    "all")
      echo -e "\n错误统计:"
      echo "错误总数: $(grep -i "error\|fail\|critical\|emerg" "$LOG_FILE" | wc -l)"
      
      echo -e "\n警告统计:"
      echo "警告总数: $(grep -i "warn\|warning\|notice" "$LOG_FILE" | wc -l)"
      
      echo -e "\n近期活动 (最后20行):"
      tail -n 20 "$LOG_FILE"
      ;;
      
    *)
      echo "未知选项: $OPTION"
      show_help
      exit 1
      ;;
  esac
  
  # 分析最频繁的IP地址（适用于Web服务器日志）
  if echo "$LOG_FILE" | grep -q "access.log"; then
    echo -e "\n访问频率最高的IP地址:"
    grep -o '[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}' "$LOG_FILE" | sort | uniq -c | sort -nr | head -n 10
  fi
  
  # 分析最近的系统错误（适用于系统日志）
  if echo "$LOG_FILE" | grep -q "syslog\|messages"; then
    echo -e "\n最近的系统服务错误:"
    grep "systemd" "$LOG_FILE" | grep -i "error\|fail" | tail -n 10
  fi
}

# 检查参数
if [ "$1" == "--help" ] || [ "$1" == "-h" ]; then
  show_help
  exit 0
fi

# 执行分析
analyze_log
