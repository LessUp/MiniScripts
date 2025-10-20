#!/bin/bash

# Linux-HealthCheck.sh
#
# 全面检查Linux系统健康状态，并生成详细的HTML报告。

# --- 文档 ---
# SYNOPSIS
#     一个全面的Linux系统健康检查工具，可生成HTML报告。
#
# DESCRIPTION
#     此脚本检查Linux系统的关键指标，包括CPU、内存、磁盘、服务、网络和日志。
#     它将所有结果编译成一个易于阅读的HTML报告，并根据问题的严重性进行颜色编码。
#
# PARAMETERS
#     -o, --output-path [PATH]
#         指定报告和日志文件的输出目录。默认为脚本所在目录。
#
# EXAMPLE
#     # 运行脚本并使用默认输出路径
#     ./Linux-HealthCheck.sh
#
#     # 指定输出目录
#     ./Linux-HealthCheck.sh -o /var/log/health-reports
# --- 文档结束 ---

# --- 全局变量和默认值 ---
OUTPUT_PATH="."
LOG_FILE=""
REPORT_FILE=""

# 存储问题的数组
declare -a ISSUES_CRITICAL
declare -a ISSUES_WARNING
declare -a ISSUES_INFO

# --- 函数定义 ---

# 日志记录函数
function write_log() {
    local level="$1"
    local message="$2"
    local timestamp=$(date +'%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
}

# 添加问题到报告
function add_issue() {
    local category="$1"
    local description="$2"
    local recommendation="$3"
    local level="$4"
    
    # 使用管道符作为分隔符
    local issue_string="$category|$description|$recommendation"

    case "$level" in
        Critical) ISSUES_CRITICAL+=("$issue_string") ;;
        Warning)  ISSUES_WARNING+=("$issue_string") ;;
        Info)     ISSUES_INFO+=("$issue_string") ;;
    esac
    write_log "$level" "$category: $description"
}

# 检查函数
function check_system_info() {
    add_issue "系统信息" "主机名: $(hostname)" "无" "Info"
    add_issue "系统信息" "内核版本: $(uname -r)" "无" "Info"
    add_issue "系统信息" "发行版: $(cat /etc/os-release | grep PRETTY_NAME | cut -d'=' -f2 | tr -d '"')" "无" "Info"
    add_issue "系统信息" "系统运行时间: $(uptime -p)" "无" "Info"
}

function check_cpu_usage() {
    # 获取1秒内的平均CPU使用率
    local usage=$(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1}')
    add_issue "CPU" "当前CPU使用率: ${usage}%" "如果持续过高，请使用 'top' 或 'htop' 检查高CPU消耗的进程。" "Info"
    if (( $(echo "$usage > 90" | bc -l) )); then
        add_issue "CPU" "CPU使用率超过90%！" "CPU负载过高，可能导致性能问题。" "Critical"
    fi
}

function check_memory_usage() {
    local total=$(free -m | awk '/^Mem:/{print $2}')
    local used=$(free -m | awk '/^Mem:/{print $3}')
    local usage_percent=$((used * 100 / total))
    add_issue "内存" "内存使用: ${used}MB / ${total}MB (${usage_percent}%)" "无" "Info"
    if [ $usage_percent -gt 90 ]; then
        add_issue "内存" "内存使用率超过90%！" "内存不足可能导致系统变慢或应用程序崩溃。" "Critical"
    fi
}

function check_disk_usage() {
    df -hP | grep '^/dev/' | while read -r line; do
        local fs=$(echo $line | awk '{print $1}')
        local size=$(echo $line | awk '{print $2}')
        local used=$(echo $line | awk '{print $3}')
        local usage_percent=$(echo $line | awk '{print $5}' | tr -d '%')
        local mount_point=$(echo $line | awk '{print $6}')
        
        add_issue "磁盘" "文件系统 '$mount_point' ($fs) 使用率: ${usage_percent}% (${used}/${size})" "无" "Info"
        if [ $usage_percent -gt 90 ]; then
            add_issue "磁盘" "磁盘分区 '$mount_point' 使用率超过90%！" "磁盘空间不足可能导致数据无法写入。请清理文件。" "Critical"
        elif [ $usage_percent -gt 80 ]; then
            add_issue "磁盘" "磁盘分区 '$mount_point' 使用率超过80%" "建议清理不必要的文件。" "Warning"
        fi
    done
}

function check_critical_services() {
    local services=("sshd" "cron" "systemd-journald") # 可根据需要添加更多服务
    for service in "${services[@]}"; do
        if systemctl is-active --quiet "$service"; then
            add_issue "服务" "服务 '$service' 正在运行。" "无" "Info"
        else
            add_issue "服务" "关键服务 '$service' 未运行！" "请使用 'systemctl status $service' 检查并启动它。" "Critical"
        fi
    done
}

function check_network() {
    local gateway=$(ip r | grep default | awk '{print $3}')
    if ping -c 1 "$gateway" > /dev/null 2>&1; then
        add_issue "网络" "成功 Ping 通默认网关 ($gateway)。" "无" "Info"
    else
        add_issue "网络" "无法 Ping 通默认网关 ($gateway)！" "网络配置或连接可能存在问题。" "Warning"
    fi
    if ping -c 1 "8.8.8.8" > /dev/null 2>&1; then
        add_issue "网络" "成功 Ping 通外部地址 (8.8.8.8)。" "无" "Info"
    else
        add_issue "网络" "无法 Ping 通外部地址 (8.8.8.8)！" "DNS或外部网络连接可能存在问题。" "Warning"
    fi
}

# HTML报告生成函数
function generate_html_report() {
    local report_date=$(date +'%Y-%m-%d %H:%M:%S')
    local critical_count=${#ISSUES_CRITICAL[@]}
    local warning_count=${#ISSUES_WARNING[@]}

    # HTML 头部
    cat > "$REPORT_FILE" <<-EOF
<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <title>Linux 系统健康检查报告</title>
    <style>
        body { font-family: 'Segoe UI', 'Microsoft YaHei', sans-serif; margin: 20px; background-color: #f4f4f9; }
        h1, h2 { color: #333; border-bottom: 2px solid #4a90e2; padding-bottom: 10px; }
        table { width: 100%; border-collapse: collapse; margin-top: 20px; box-shadow: 0 2px 5px rgba(0,0,0,0.1); }
        th, td { padding: 12px; text-align: left; border: 1px solid #ddd; }
        th { background-color: #4a90e2; color: white; }
        .summary-box { padding: 20px; background-color: #eaf2f8; border-left: 5px solid #4a90e2; margin-bottom: 20px; }
        .critical { background-color: #f8d7da; color: #721c24; }
        .warning { background-color: #fff3cd; color: #856404; }
        .info { background-color: #d4edda; color: #155724; }
    </style>
</head>
<body>
    <h1>Linux 系统健康检查报告</h1>
    <div class="summary-box">
        <strong>报告生成时间:</strong> $report_date<br>
        <strong>主机名:</strong> $(hostname)<br>
        <strong class="critical">严重问题:</strong> $critical_count<br>
        <strong class="warning">警告问题:</strong> $warning_count<br>
    </div>

EOF

    # 生成问题表格
    generate_issue_table "严重问题" "Critical" "${ISSUES_CRITICAL[@]}" >> "$REPORT_FILE"
    generate_issue_table "警告问题" "Warning" "${ISSUES_WARNING[@]}" >> "$REPORT_FILE"
    generate_issue_table "信息摘要" "Info" "${ISSUES_INFO[@]}" >> "$REPORT_FILE"

    # HTML 尾部
    echo "</body></html>" >> "$REPORT_FILE"
}

function generate_issue_table() {
    local title="$1"
    local level="$2"
    local -a issues=("$3")

    if [ ${#issues[@]} -eq 0 ]; then return; fi

    echo "<h2>$title</h2>" 
    echo "<table>" 
    echo "<tr><th>类别</th><th>描述</th><th>建议</th></tr>"

    for issue in "${issues[@]}"; do
        IFS='|' read -r category description recommendation <<< "$issue"
        echo "<tr class='${level,,}'><td>$category</td><td>$description</td><td>$recommendation</td></tr>"
    done

    echo "</table>"
}

# --- 主逻辑 ---

# 解析命令行参数
while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
        -o|--output-path)
        OUTPUT_PATH="$2"
        shift; shift;;
        *)
        echo "未知参数: $1"
        exit 1;;
    esac
done

# 创建输出目录和文件
mkdir -p "$OUTPUT_PATH"
LOG_FILE="$OUTPUT_PATH/HealthCheck_$(date +'%Y%m%d_%H%M%S').log"
REPORT_FILE="$OUTPUT_PATH/HealthCheck_Report_$(date +'%Y%m%d_%H%M%S').html"
touch "$LOG_FILE"

write_log "Info" "===== 开始系统健康检查 ====="

# 执行所有检查
check_system_info
check_cpu_usage
check_memory_usage
check_disk_usage
check_critical_services
check_network

# 生成报告
generate_html_report

write_log "Info" "===== 健康检查完成 ====="
write_log "Info" "日志文件: $LOG_FILE"
write_log "Info" "报告文件: $REPORT_FILE"

printf "\n${C_GREEN}健康检查已完成。${C_NC}\n"
printf "报告已生成: %s\n" "$REPORT_FILE"
