#!/bin/bash
# Ubuntu系统监控工具
# 用法: ./03-system-monitor.sh

# 显示标题
echo "===== Ubuntu系统监控 ====="
echo "当前时间: $(date)"
echo

# 检查CPU使用情况
echo "--- CPU使用情况 ---"
top -bn1 | head -n 5
echo

# 检查内存使用情况
echo "--- 内存使用情况 ---"
free -h
echo

# 检查磁盘使用情况
echo "--- 磁盘使用情况 ---"
df -h
echo

# 检查系统负载
echo "--- 系统负载 ---"
uptime
echo

# 检查进程使用资源最多的前5个进程
echo "--- 资源占用最多的进程 ---"
ps aux --sort=-%cpu | head -n 6
echo

# 检查网络连接
echo "--- 网络连接 ---"
netstat -tuln | head -n 20
echo

# 检查最近的系统日志
echo "--- 最近的系统日志 ---"
journalctl -n 10 --no-pager
