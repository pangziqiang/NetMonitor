#!/bin/bash
# ============================================================
# NetMonitor vs 竞品 — 综合基准测试脚本
# 对比项: CPU / 内存 / 线程 / 启动时间 / 磁盘占用 / 架构
# ============================================================
set -euo pipefail

APPS_DIR="/Applications"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPORT_DIR="${1:-$SCRIPT_DIR/../benchmark-report}"
TIMESTAMP=$(date '+%Y-%m-%d_%H-%M-%S')
REPORT_FILE="$REPORT_DIR/benchmark-report-$TIMESTAMP.md"
HTML_FILE="$REPORT_DIR/benchmark-report-$TIMESTAMP.html"
DATA_DIR="$REPORT_DIR/data-$TIMESTAMP"
RESULTS_DIR="$DATA_DIR/results"
SAMPLES=8
SAMPLE_INTERVAL=5
WARMUP=5

mkdir -p "$RESULTS_DIR"

APPS=(
  "NetMonitor:NetMonitor"
  "HagimiMonitor:HagimiMonitor"
  "Stats:Stats"
  "NetWorker Pro:NetWorker Pro"
)

cleanup() {
  for entry in "${APPS[@]}"; do
    name="${entry#*:}"
    pkill -x "$name" 2>/dev/null || true
  done
  sleep 1
}

thread_count() {
  local pid=$1
  local count=0
  if command -v python3 &>/dev/null; then
    count=$(python3 -c "import psutil; print(psutil.Process($pid).num_threads())" 2>/dev/null || echo "0")
  else
    # Fallback: use ps -M (macOS) to list threads
    count=$(ps -M "$pid" 2>/dev/null | wc -l | tr -d ' ')
    [ -z "$count" ] && count=0
    # ps -M output: header + thread lines
    count=$((count > 0 ? count - 1 : 0))
  fi
  echo "$count"
}

sample_app() {
  local pid=$1 sample_num=$2 data_file=$3
  local ps_out
  ps_out=$(ps -p "$pid" -o pcpu=,rss=,vsize= 2>/dev/null || echo "0 0 0")
  read -r cpu rss vsz <<< "$ps_out"
  cpu=$(echo "$cpu" | tr -d ' ' | sed 's/,/./')
  rss=$(echo "$rss" | tr -d ' ')
  [ -z "$rss" ] && rss=0
  local rss_mb=$((rss / 1024))
  [ "$rss_mb" -lt 0 ] && rss_mb=0

  local thcount=$(thread_count "$pid")

  local fd_count=0
  if command -v lsof &>/dev/null; then
    fd_count=$(lsof -p "$pid" 2>/dev/null | wc -l | tr -d ' ')
  fi

  echo "$sample_num|$cpu|$rss_mb|$thcount|$fd_count" >> "$data_file"
  echo "   [S$sample_num] CPU:${cpu}% MEM:${rss_mb}MB THR:${thcount} FD:${fd_count}"
}

save_result() {
  local app="$1" key="$2" val="$3"
  echo "$key=$val" >> "$RESULTS_DIR/${app// /_}.txt"
}

get_result() {
  local app="$1" key="$2"
  grep "^$key=" "$RESULTS_DIR/${app// /_}.txt" 2>/dev/null | cut -d'=' -f2 || echo ""
}

# ============================================================
echo "=============================================="
echo "  macOS 菜单栏监控 App 综合基准测试"
echo "  $(date '+%Y-%m-%d %H:%M:%S') | $(uname -m) | macOS $(sw_vers -productVersion)"
echo "=============================================="

cleanup

SYS_MEM=$(sysctl hw.memsize | awk '{print $2/1073741824}')
SYS_CPU_CORES=$(sysctl hw.ncpu | awk '{print $2}')
echo "  系统: ${SYS_MEM}GB RAM, ${SYS_CPU_CORES}核 CPU"
echo ""

for entry in "${APPS[@]}"; do
  display_name="${entry%%:*}"
  binary_name="${entry#*:}"
  app_path="$APPS_DIR/$display_name.app"

  echo "===== $display_name ====="

  if [ ! -d "$app_path" ]; then
    echo "  ! 未找到 $app_path，跳过"
    continue
  fi

  APP_DATA="$DATA_DIR/${display_name// /_}.csv"
  > "$APP_DATA"

  # Binary info
  binary_path="$app_path/Contents/MacOS/$binary_name"
  if [ -f "$binary_path" ]; then
    bin_size=$(stat -f%z "$binary_path" 2>/dev/null | awk '{printf "%.1f", $1/1048576}')
    bin_arch=$(file "$binary_path" 2>/dev/null | grep -oE '(arm64|x86_64)' | sort -u | tr '\n' '/' | sed 's|/$||')
  else
    bin_size="N/A"; bin_arch="N/A"
  fi
  app_size=$(du -sm "$app_path" 2>/dev/null | awk '{print $1}')
  save_result "$display_name" "bin_size" "$bin_size"
  save_result "$display_name" "arch" "$bin_arch"
  save_result "$display_name" "app_size" "$app_size"
  echo "  二进制: ${bin_size}MB | 架构: ${bin_arch} | App包: ${app_size}MB"

  # Launch time (using python for ms precision)
  echo "  启动测试..."
  pkill -x "$binary_name" 2>/dev/null || true
  sleep 1

  launch_time=0
  if command -v python3 &>/dev/null; then
    launch_script=$(cat <<'PYEOF'
import subprocess, time, sys
bundle = sys.argv[1]
name = sys.argv[2]
start = time.perf_counter()
subprocess.run(['open', bundle], capture_output=True)
pid = None
for _ in range(30):
    try:
        result = subprocess.run(['pgrep', '-x', name], capture_output=True, text=True, timeout=1)
        out = result.stdout.strip()
        if out:
            pid = out.split('\n')[0]
            break
    except:
        pass
    time.sleep(0.1)
elapsed = int((time.perf_counter() - start) * 1000)
print(f"{elapsed}|{pid or 'N/A'}")
PYEOF
    )
    lt_result=$(python3 -c "$launch_script" "$app_path" "$binary_name" 2>/dev/null || echo "0|")
    launch_time=$(echo "$lt_result" | cut -d'|' -f1)
    pid=$(echo "$lt_result" | cut -d'|' -f2)
  else
    start_time=$(date +%s)
    open "$app_path"
    pid=""
    for i in $(seq 1 30); do
      pid=$(pgrep -x "$binary_name" 2>/dev/null || echo "")
      [ -n "$pid" ] && break
      sleep 0.1
    done
    end_time=$(date +%s)
    launch_time=$(( (end_time - start_time) * 1000 ))
  fi

  if [ -z "$pid" ] || [ "$pid" = "N/A" ]; then
    echo "  ! 启动失败"
    save_result "$display_name" "launch_time" "N/A"
    continue
  fi
  save_result "$display_name" "launch_time" "$launch_time"
  echo "  启动: ${launch_time}ms | PID: ${pid}"

  # Warmup
  sleep $WARMUP

  # Sampling
  echo "  采样 ${SAMPLES}次 x ${SAMPLE_INTERVAL}s..."
  for i in $(seq 1 $SAMPLES); do
    if ! kill -0 "$pid" 2>/dev/null; then
      echo "  ! 进程已退出"
      break
    fi
    sample_app "$pid" "$i" "$APP_DATA"
    sleep $SAMPLE_INTERVAL
  done

  # Aggregate
  if [ -f "$APP_DATA" ]; then
    avg_cpu=$(awk -F'|' '{c+=$2;n++} END{if(n>0) printf "%.2f", c/n}' "$APP_DATA")
    max_cpu=$(awk -F'|' 'BEGIN{m=0}{if($2+0>m+0)m=$2}END{printf "%.1f",m}' "$APP_DATA")
    avg_mem=$(awk -F'|' '{m+=$3;n++} END{if(n>0) printf "%.0f", m/n}' "$APP_DATA")
    max_mem=$(awk -F'|' 'BEGIN{m=0}{if($3+0>m+0)m=$3}END{print m}' "$APP_DATA")
    avg_thr=$(awk -F'|' '{t+=$4;n++} END{if(n>0) printf "%.0f", t/n}' "$APP_DATA")
    max_thr=$(awk -F'|' 'BEGIN{m=0}{if($4+0>m+0)m=$4}END{print m}' "$APP_DATA")
    avg_fd=$(awk -F'|' '{f+=$5;n++} END{if(n>0) printf "%.0f", f/n}' "$APP_DATA")

    save_result "$display_name" "avg_cpu" "$avg_cpu"
    save_result "$display_name" "max_cpu" "$max_cpu"
    save_result "$display_name" "avg_mem" "$avg_mem"
    save_result "$display_name" "max_mem" "$max_mem"
    save_result "$display_name" "avg_thr" "$avg_thr"
    save_result "$display_name" "max_thr" "$max_thr"
    save_result "$display_name" "avg_fd" "$avg_fd"

    echo "  == $display_name 统计 =="
    echo "  CPU: avg ${avg_cpu}% / peak ${max_cpu}%"
    echo "  MEM: avg ${avg_mem}MB / peak ${max_mem}MB"
    echo "  THR: avg ${avg_thr} / peak ${max_thr}"
    echo "  FD:  avg ${avg_fd}"
  fi

  pkill -x "$binary_name" 2>/dev/null || true
  sleep 1
  echo ""
done

cleanup

# ============================================================
# Generate report
# ============================================================
echo "========== 生成报告 =========="

# Get tested app list (line-delimited, handles spaces)
APPS_FILE="$DATA_DIR/tested_apps.txt"
> "$APPS_FILE"
for entry in "${APPS[@]}"; do
  app="${entry%%:*}"
  [ -n "$(get_result "$app" "avg_cpu")" ] && echo "$app" >> "$APPS_FILE"
done
echo "  成功测试: $(paste -s -d'|' "$APPS_FILE")"

# Find best (minimum) values
best_cpu=999; best_mem=999; best_thr=999; best_launch=999999; best_size=999
while IFS= read -r app; do
  v=$(get_result "$app" "avg_cpu"); [ -n "$v" ] && [ "$(echo "$v < $best_cpu" | bc -l 2>/dev/null)" = "1" ] && best_cpu=$v
  v=$(get_result "$app" "avg_mem"); [ -n "$v" ] && [ "$v" -lt "$best_mem" ] && best_mem=$v
  v=$(get_result "$app" "avg_thr"); [ -n "$v" ] && [ "$v" -lt "$best_thr" ] && best_thr=$v
  v=$(get_result "$app" "launch_time"); [ -n "$v" ] && [ "$v" -lt "$best_launch" ] && best_launch=$v
  v=$(get_result "$app" "app_size"); [ -n "$v" ] && [ "$v" -lt "$best_size" ] && best_size=$v
done < "$APPS_FILE"

# Find max for normalization
max_cpu=0; max_mem=0; max_thr=0; max_launch=0; max_size=0
while IFS= read -r app; do
  v=$(get_result "$app" "avg_cpu"); [ -n "$v" ] && [ "$(echo "$v > $max_cpu" | bc -l 2>/dev/null)" = "1" ] && max_cpu=$v
  v=$(get_result "$app" "avg_mem"); [ -n "$v" ] && [ "$v" -gt "$max_mem" ] && max_mem=$v
  v=$(get_result "$app" "avg_thr"); [ -n "$v" ] && [ "$v" -gt "$max_thr" ] && max_thr=$v
  v=$(get_result "$app" "launch_time"); [ -n "$v" ] && [ "$v" -gt "$max_launch" ] && max_launch=$v
  v=$(get_result "$app" "app_size"); [ -n "$v" ] && [ "$v" -gt "$max_size" ] && max_size=$v
done < "$APPS_FILE"
[ "$(echo "$max_cpu == 0" | bc -l)" = "1" ] && max_cpu=1
[ "$max_mem" -eq 0 ] && max_mem=1
[ "$max_thr" -eq 0 ] && max_thr=1
[ "$max_launch" -eq 0 ] && max_launch=1
[ "$max_size" -eq 0 ] && max_size=1

# Helper: format best value with trophy
best_fmt() { local v=$1 b=$2 u=$3; [ "$(echo "$v == $b" | bc -l 2>/dev/null)" = "1" ] && printf "🏆 **%s%s**" "$v" "$u" || printf "%s%s" "$v" "$u"; }

# Write report
{
  echo "# macOS 菜单栏网络监控 App 对比评测报告"
  echo ""
  echo "> **测试日期**: $(date '+%Y-%m-%d %H:%M:%S')"
  echo "> **测试平台**: macOS $(sw_vers -productVersion) ($(uname -m))"
  echo "> **系统内存**: ${SYS_MEM}GB | **CPU 核心**: ${SYS_CPU_CORES}"
  echo "> **测试方法**: 每 App 启动后预热 ${WARMUP}s，采样 ${SAMPLES} 次，间隔 ${SAMPLE_INTERVAL}s"
  echo ""
  echo "---"
  echo ""
  echo "## 综合评分表"
  echo ""
  echo "| 指标 | NetMonitor | HagimiMonitor | Stats | NetWorker Pro |"
  echo "|------|:-------------:|:-------------:|:-----:|:-------------:|"

  # CPU avg row
  echo -n "| **平均 CPU** |"
  cat "$APPS_FILE" | while IFS= read -r app; do echo -n " $(best_fmt "$(get_result "$app" "avg_cpu")" "$best_cpu" "%") |"; done
  echo ""

  # CPU max row
  echo -n "| **峰值 CPU** |"
  cat "$APPS_FILE" | while IFS= read -r app; do echo -n " $(get_result "$app" "max_cpu")% |"; done
  echo ""

  # MEM avg row
  echo -n "| **平均内存** |"
  cat "$APPS_FILE" | while IFS= read -r app; do echo -n " $(best_fmt "$(get_result "$app" "avg_mem")" "$best_mem" "MB") |"; done
  echo ""

  # MEM max row
  echo -n "| **峰值内存** |"
  cat "$APPS_FILE" | while IFS= read -r app; do echo -n " $(get_result "$app" "max_mem")MB |"; done
  echo ""

  # Threads row
  echo -n "| **平均线程** |"
  cat "$APPS_FILE" | while IFS= read -r app; do echo -n " $(best_fmt "$(get_result "$app" "avg_thr")" "$best_thr" "") |"; done
  echo ""

  # FD row
  echo -n "| **平均 FD** |"
  cat "$APPS_FILE" | while IFS= read -r app; do echo -n " $(get_result "$app" "avg_fd") |"; done
  echo ""

  # Launch time row
  echo -n "| **启动时间** |"
  cat "$APPS_FILE" | while IFS= read -r app; do echo -n " $(best_fmt "$(get_result "$app" "launch_time")" "$best_launch" "ms") |"; done
  echo ""

  # App size row
  echo -n "| **App 大小** |"
  cat "$APPS_FILE" | while IFS= read -r app; do echo -n " $(best_fmt "$(get_result "$app" "app_size")" "$best_size" "MB") |"; done
  echo ""

  # Binary size row
  echo -n "| **二进制大小** |"
  cat "$APPS_FILE" | while IFS= read -r app; do echo -n " $(get_result "$app" "bin_size")MB |"; done
  echo ""

  # Architecture row
  echo -n "| **架构** |"
  cat "$APPS_FILE" | while IFS= read -r app; do echo -n " $(get_result "$app" "arch") |"; done
  echo ""

  echo ""
  echo "> = 该组最优（数值越低越好）"
  echo ""
  echo "---"
  echo ""
  echo "## 详细分项分析"
  echo ""
  echo "### 1. CPU 使用率"
  echo ""
  echo "CPU 占用是菜单栏应用的关键指标 — 长期运行在后台，越省电越好。"
  echo ""
  echo "| App | 平均 CPU | 峰值 CPU | 评价 |"
  echo "|-----|:--------:|:--------:|:----:|"

  cat "$APPS_FILE" | while IFS= read -r app; do
    avg=$(get_result "$app" "avg_cpu")
    max=$(get_result "$app" "max_cpu")
    if [ "$(echo "$avg < 1.0" | bc -l)" = "1" ]; then cmt="极低"; icon="🟢"
    elif [ "$(echo "$avg < 3.0" | bc -l)" = "1" ]; then cmt="较低"; icon="🟡"
    elif [ "$(echo "$avg < 5.0" | bc -l)" = "1" ]; then cmt="中等"; icon="🟠"
    else cmt="偏高"; icon="🔴"; fi
    echo "| $app | ${avg}% | ${max}% | ${icon} ${cmt} |"
  done

  echo ""
  echo "**分析**: 菜单栏应用应尽量保持在 CPU 占用 3% 以下，避免影响笔记本续航和风扇噪音。"
  echo ""
  echo "### 2. 内存占用"
  echo ""
  echo "| App | 平均内存 | 峰值内存 | 评价 |"
  echo "|-----|:--------:|:--------:|:----:|"

  cat "$APPS_FILE" | while IFS= read -r app; do
    avg=$(get_result "$app" "avg_mem")
    max=$(get_result "$app" "max_mem")
    if [ "$avg" -lt 20 ]; then cmt="极低"; icon="🟢"
    elif [ "$avg" -lt 50 ]; then cmt="较低"; icon="🟡"
    elif [ "$avg" -lt 100 ]; then cmt="中等"; icon="🟠"
    else cmt="偏高"; icon="🔴"; fi
    echo "| $app | ${avg}MB | ${max}MB | ${icon} ${cmt} |"
  done

  echo ""
  echo "**分析**: 菜单栏应用典型内存占用在 20-80MB 范围。内存越高，系统在内存压力下换页的可能性越大。"
  echo ""
  echo "### 3. 线程与文件描述符"
  echo ""
  echo "| App | 平均线程 | 峰值线程 | 平均 FD | 评价 |"
  echo "|-----|:--------:|:--------:|:-------:|:----:|"

  cat "$APPS_FILE" | while IFS= read -r app; do
    thr=$(get_result "$app" "avg_thr")
    mthr=$(get_result "$app" "max_thr")
    fd=$(get_result "$app" "avg_fd")
    if [ "$thr" -lt 10 ]; then cmt="精简"; icon="🟢"
    elif [ "$thr" -lt 20 ]; then cmt="适中"; icon="🟡"
    elif [ "$thr" -lt 30 ]; then cmt="偏多"; icon="🟠"
    else cmt="过多"; icon="🔴"; fi
    echo "| $app | ${thr} | ${mthr} | ${fd} | ${icon} ${cmt} |"
  done

  echo ""
  echo "**分析**: 线程数反映应用的并发设计。过多的线程增加上下文切换开销和内核内存压力。"
  echo ""
  echo "### 4. 启动速度与磁盘占用"
  echo ""
  echo "| App | 启动时间 | App 大小 | 二进制大小 | 架构 |"
  echo "|-----|:--------:|:--------:|:----------:|:----:|"

  cat "$APPS_FILE" | while IFS= read -r app; do
    lt=$(get_result "$app" "launch_time")
    as=$(get_result "$app" "app_size")
    bs=$(get_result "$app" "bin_size")
    ar=$(get_result "$app" "arch")
    echo "| $app | ${lt}ms | ${as}MB | ${bs}MB | ${ar:-N/A} |"
  done

  echo ""
  echo "**分析**: 启动时间影响用户体验。Apple Silicon 原生 App 因无需 Rosetta 转译通常启动更快。App 大小影响首次下载和更新耗时。"
  echo ""
  echo "### 5. 架构支持"
  echo ""
  echo "| App | 架构 | Apple Silicon 原生 |"
  echo "|-----|:----:|:-----------------:|"

  cat "$APPS_FILE" | while IFS= read -r app; do
    ar=$(get_result "$app" "arch")
    if echo "$ar" | grep -q "/"; then native="是 (Universal)"
    elif echo "$ar" | grep -q "arm64"; then native="是 (纯 arm64)"
    else native="否 (需 Rosetta)"; fi
    echo "| $app | ${ar} | ${native} |"
  done

  echo ""
  echo "**分析**: Apple Silicon 上运行 Intel 架构 App 需要 Rosetta 2 转译，会增加约 20-30% 的性能开销和内存占用。"
  echo ""
  echo "---"
  echo ""
  echo "## 综合评分"
  echo ""
  echo "加权评分规则（越低越好，归一化 0-10）："
  echo ""
  echo "| 权重 | 指标 | 说明 |"
  echo "|:----:|:-----|:-----|"
  echo "| 30% | CPU 平均 | 最影响续航和发热 |"
  echo "| 25% | 内存平均 | 影响系统多任务能力 |"
  echo "| 15% | 线程数 | 反映并发设计效率 |"
  echo "| 15% | 启动时间 | 影响用户体验 |"
  echo "| 10% | App 大小 | 影响下载和更新速度 |"
  echo "| 5% | 架构支持 | Universal/arm64 加分 |"
  echo ""
  echo "| 排名 | App | 综合得分 | CPU(30%) | 内存(25%) | 线程(15%) | 启动(15%) | 大小(10%) | 架构(5%) |"
  echo "|:---:|:---|:--------:|:--------:|:---------:|:---------:|:---------:|:---------:|:--------:|"

  # Compute and sort scores
  SCORE_FILE="$DATA_DIR/scores.tmp"
  > "$SCORE_FILE"

  cat "$APPS_FILE" | while IFS= read -r app; do
    cpu=$(get_result "$app" "avg_cpu")
    mem=$(get_result "$app" "avg_mem")
    thr=$(get_result "$app" "avg_thr")
    lt=$(get_result "$app" "launch_time")
    s=$(get_result "$app" "app_size")
    ar=$(get_result "$app" "arch")

    cpu_s=$(echo "scale=4; (1 - ($cpu / $max_cpu)) * 10" | bc)
    mem_s=$(echo "scale=4; (1 - ($mem / $max_mem)) * 10" | bc)
    thr_s=$(echo "scale=4; (1 - ($thr / $max_thr)) * 10" | bc)
    lt_s=$(echo "scale=4; (1 - ($lt / $max_launch)) * 10" | bc)
    size_s=$(echo "scale=4; (1 - ($s / $max_size)) * 10" | bc)

    if echo "$ar" | grep -q "/"; then arch_s=1.0
    elif echo "$ar" | grep -q "arm64"; then arch_s=2.0
    else arch_s=0; fi

    total=$(echo "scale=4; $cpu_s*0.30 + $mem_s*0.25 + $thr_s*0.15 + $lt_s*0.15 + $size_s*0.10 + $arch_s*0.05" | bc)
    [ "$(echo "$total < 0" | bc -l)" = "1" ] && total=0

    echo "$total|$app|$cpu_s|$mem_s|$thr_s|$lt_s|$size_s|$arch_s" >> "$SCORE_FILE"
  done

  sort -t'|' -k1 -rn "$SCORE_FILE" | awk -F'|' 'BEGIN{r=1}{printf "| %d | %s | **%.2f** | %.2f | %.2f | %.2f | %.2f | %.2f | %.2f |\n", r, $2, $1, $3, $4, $5, $6, $7, $8; r++}'

  echo ""
  echo "---"
  echo ""
  echo "## 总结"
  echo ""
  echo "> 本报告为自动化基准测试生成，测试环境为固定条件，实际使用体验可能因系统负载、网络环境和使用模式而异。"
  echo ""
  echo "### 关键发现"
  echo ""
  echo "- CPU 和内存是菜单栏应用最重要的指标 — 直接影响续航和系统流畅度"
  echo "- Apple Silicon 原生架构的 App 在启动速度和能效上更有优势"
  echo ""
  echo "### 评分说明"
  echo ""
  echo "- 权重设计侧重 CPU 和内存占用（合计 55%）"
  echo "- 架构支持加分：Universal 二进制得 1 分，纯 arm64 得 2 分"
  echo "- 得分范围 0-10 分，越高越好"
  echo ""
  echo "---"
  echo ""
  echo "*报告生成时间: $(date '+%Y-%m-%d %H:%M:%S')*"
  echo "*生成脚本: compare-benchmark.sh*"
} > "$REPORT_FILE"

echo "  Markdown: $REPORT_FILE"

# Generate HTML via Python (avoid bash quoting issues)
echo "  HTML..."
python3 "$SCRIPT_DIR/compare-benchmark-html.py" "$REPORT_FILE" "$HTML_FILE" || cp "$REPORT_FILE" "$HTML_FILE"

echo "  HTML: $HTML_FILE"

echo ""
echo "== 测试完成 =="
echo "  报告: $REPORT_FILE"
echo "  数据: $DATA_DIR"
echo "  HTML: $HTML_FILE"
echo "================"
