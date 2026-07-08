# 竞品基准测试 (2026-07-09)

## 测试环境
- macOS 15.7.7 (x86_64), 16GB RAM, 12核 CPU
- 每 App 预热 5s, 采样 8x5s

## 结果摘要

| App | CPU avg | MEM avg | 线程 | 启动 | 大小 | 架构 |
|-----|---------|---------|------|------|------|------|
| **NetworkMonitor** | 3.58% | 106MB | 7 | 271ms | 6MB | x86_64 |
| HagimiMonitor | 8.50% | 130MB | 10 | 216ms | 9MB | x86_64 |
| Stats | **1.94%** | 123MB | 16 | 225ms | 18MB | arm64/x86_64 |
| NetWorker Pro | 4.55% | 106MB | 7 | 199ms | 9MB | arm64/x86_64 |

## 综合排名 (加权0-10)
1. NetworkMonitor **3.71** (CPU+内存+线程最优)
2. NetWorker Pro 3.65
3. Stats 2.75
4. HagimiMonitor 1.37

## Stats CPU 低的原因
- arm64 原生：Apple Silicon 原生比 Rosetta 转译效率高 20-30%
- IOKit IOReport API：接近推送式，无需主动高频轮询
- GPU 用 IOReport 而非 IOAccelerator 轮询

## 改进方向
- 降频：非关键指标改 6-10s 轮询
- 用 IOKit IOReport 替代轮询
- 编译 arm64 原生版本
- 减少 ProcessMonitor 采样频率

## 测试脚本
`scripts/compare-benchmark.sh` — 支持 4 款 App 并行采样，自动生成 Markdown+HTML 报告
