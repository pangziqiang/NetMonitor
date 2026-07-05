#!/bin/bash
# 性能基准测试：启动 App，采样 CPU/内存，对比历史阈值
set -euo pipefail

APP="$1"
BASELINE="${2:-.github/performance_baseline.txt}"
SAMPLES=6
WAIT=5

if [ ! -d "$APP" ]; then
  echo "用法: $0 <NetworkMonitor.app> [基准文件]"
  exit 1
fi

echo "==> 性能基准测试 =="
echo "    App: $APP"
echo "    采样: ${SAMPLES}次, 间隔 ${WAIT}s"

# 杀掉旧进程
pkill -f "NetworkMonitor.app" 2>/dev/null || true
sleep 2

# 启动 App
open "$APP"
sleep 3

# 采样
TOTAL_CPU=0
TOTAL_MEM=0
SUCCESS=0

for i in $(seq 1 $SAMPLES); do
  PID=$(pgrep -f "NetworkMonitor.app/Contents/MacOS" | head -1 || echo "")
  if [ -z "$PID" ]; then
    echo "   [${i}] App 未运行"
    continue
  fi
  CPU=$(ps -p "$PID" -o pcpu= 2>/dev/null | tr -d ' ' || echo "0")
  RSS=$(ps -p "$PID" -o rss= 2>/dev/null | tr -d ' ' || echo "0")
  MEM=$((RSS / 1024))
  TOTAL_CPU=$(echo "$TOTAL_CPU + $CPU" | bc)
  TOTAL_MEM=$((TOTAL_MEM + MEM))
  SUCCESS=$((SUCCESS + 1))
  echo "   [${i}] CPU: ${CPU}%  MEM: ${MEM}MB"
  sleep $WAIT
done

pkill -f "NetworkMonitor.app" 2>/dev/null || true

if [ $SUCCESS -eq 0 ]; then
  echo "❌ 采样失败"
  exit 1
fi

AVG_CPU=$(echo "scale=2; $TOTAL_CPU / $SUCCESS" | bc)
AVG_MEM=$((TOTAL_MEM / SUCCESS))

echo ""
echo "==> 结果 =="
echo "    CPU: ${AVG_CPU}%"
echo "    MEM: ${AVG_MEM}MB"

# 保存基准
echo "${AVG_CPU} ${AVG_MEM}" > "$BASELINE"
echo "    基准已保存: $BASELINE"

# 对比历史
if [ -f "${BASELINE}.history" ] && [ "$(wc -l < "${BASELINE}.history")" -gt 0 ]; then
  HIST_AVG=$(awk '{cpu+=$1; mem+=$2; n++} END {if(n>0) printf "%.2f %d", cpu/n, mem/n}' "${BASELINE}.history")
  HIST_CPU=$(echo "$HIST_AVG" | awk '{print $1}')
  HIST_MEM=$(echo "$HIST_AVG" | awk '{print $2}')
  
  CPU_DIFF=$(echo "$AVG_CPU - $HIST_CPU" | bc)
  MEM_DIFF=$((AVG_MEM - HIST_MEM))
  
  echo ""
  echo "==> 对比历史 =="
  echo "    CPU: ${AVG_CPU}% (历史: ${HIST_CPU}%, 变化: ${CPU_DIFF}%)"
  echo "    MEM: ${AVG_MEM}MB (历史: ${HIST_MEM}MB, 变化: ${MEM_DIFF}MB)"
  
  CPU_THRESHOLD=2.0
  MEM_THRESHOLD=30
  
  if (( $(echo "$CPU_DIFF > $CPU_THRESHOLD" | bc -l) )); then
    echo "⚠️  CPU 超阈值 (${CPU_THRESHOLD}%)"
  fi
  if [ $MEM_DIFF -gt $MEM_THRESHOLD ]; then
    echo "⚠️  MEM 超阈值 (${MEM_THRESHOLD}MB)"
  fi
fi

# 追加到历史
echo "${AVG_CPU} ${AVG_MEM}" >> "${BASELINE}.history"

echo ""
echo "✅ 性能测试完成"