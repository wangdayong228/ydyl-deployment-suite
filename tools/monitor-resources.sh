#! /bin/bash
set -euo pipefail

# 简单的 CPU/内存/磁盘监控脚本（Linux 专用）
# 用法：
#   ./monitor-resources.sh [采样间隔秒] [输出文件路径]
#
# 示例：
#   ./monitor-resources.sh           # 默认每 5 秒采样一次，输出到 ./resource-usage.log
#   ./monitor-resources.sh 2 /tmp/usage.log

INTERVAL="${1:-5}"
OUTPUT_FILE="${2:-./resource-usage.log}"

if [[ "${INTERVAL}" -le 0 ]]; then
  echo "采样间隔必须为正整数，当前：${INTERVAL}" >&2
  exit 1
fi

OS_NAME="$(uname -s)"

if [[ "${OS_NAME}" != "Linux" ]]; then
  echo "本脚本仅支持 Linux，当前系统为：${OS_NAME}" >&2
  exit 1
fi

if ! command -v top >/dev/null 2>&1; then
  echo "未找到 top 命令，请先确保系统自带或安装 top。" >&2
  exit 1
fi

if ! command -v free >/dev/null 2>&1; then
  echo "Linux 环境未找到 free 命令，请先安装（一般在 procps 或 procps-ng 包中）" >&2
  exit 1
fi

if ! command -v df >/dev/null 2>&1; then
  echo "未找到 df 命令，请先安装 coreutils（一般系统自带）。" >&2
  exit 1
fi

# 如果文件不存在，先写表头
if [[ ! -f "${OUTPUT_FILE}" ]]; then
  echo "timestamp,cpu_user_percent,cpu_sys_percent,cpu_idle_percent,mem_used_mb,mem_free_mb,mem_available_mb,disk_used_mb,disk_avail_mb,disk_used_percent" >> "${OUTPUT_FILE}"
fi

echo "开始监控资源使用（CPU/内存/磁盘）：间隔 ${INTERVAL}s，输出文件：${OUTPUT_FILE}"
echo "按 Ctrl+C 结束监控。"

while true; do
  timestamp="$(date +"%Y-%m-%d %H:%M:%S")"

  # CPU：从 top 的 Cpu(s) 行解析 user/sys/idle
  cpu_line="$(LC_ALL=C top -b -n1 | grep "Cpu(s)" | head -n1 || true)"
  if [[ -z "${cpu_line}" ]]; then
    echo "获取 CPU 信息失败" >&2
    cpu_user=""; cpu_sys=""; cpu_idle=""
  else
    # 形如：Cpu(s):  4.4%us,  2.5%sy,  0.0%ni, 92.7%id, ...
    cpu_user="$(echo "${cpu_line}" | awk -F',' '{print $1}' | awk '{print $2}' | tr -d '%')"
    cpu_sys="$(echo  "${cpu_line}" | awk -F',' '{print $2}' | awk '{print $1}' | tr -d '%')"
    cpu_idle="$(echo "${cpu_line}" | awk -F',' '{print $4}' | awk '{print $1}' | tr -d '%')"
  fi

  # 内存：使用 free -m，单位 MB
  # total used free shared buff/cache available
  read -r _ mem_total mem_used mem_free _ _ mem_available < <(free -m | awk 'NR==2 {print $1,$2,$3,$4,$5,$6,$7}')

  # 磁盘：使用 df -Pm /，单位 MB，只看根分区
  # Filesystem 1024-blocks Used Available Capacity Mounted on
  read -r _ disk_total_mb disk_used_mb disk_avail_mb disk_used_percent_raw _ < <(df -Pm / | awk 'NR==2 {print $1,$2,$3,$4,$5,$6}')
  disk_used_percent="${disk_used_percent_raw%%%}"  # 去掉 %

  echo "${timestamp},${cpu_user},${cpu_sys},${cpu_idle},${mem_used},${mem_free},${mem_available},${disk_used_mb},${disk_avail_mb},${disk_used_percent}" >> "${OUTPUT_FILE}"

  sleep "${INTERVAL}"
done


