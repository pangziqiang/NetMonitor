# 优化计划

目标：从 3.58% CPU 降到 2% 以下，对标 Stats（1.94%）。

---

## 一、当前问题分析

### 你的应用在干什么（每 3 秒）

```
┌─────────────────────────────────────────────────────────┐
│  每 3 秒循环                                            │
├─────────────────────────────────────────────────────────┤
│  1. 读网速     getifaddrs()          → 遍历所有网卡      │
│  2. 读 CPU     host_processor_info() → 内核调用          │
│  3. 读内存     host_statistics64()   → 内核调用          │
│  4. 读 GPU     IOAccelerator         → 遍历所有 GPU      │
│  5. 读温度     SMC rotation          → 每次读一组传感器   │
│  6. 读进程     proc_listallpids()    → 遍历所有进程      │
│  7. 读进程网络  nettop 子进程         → fork+exec+解析    │
└─────────────────────────────────────────────────────────┘
```

**问题**：7 件事每 3 秒做一遍，有些根本不需要这么频繁。

### Stats 为什么低

1. **arm64 原生**：你的 App 是 x86_64，通过 Rosetta 转译运行，CPU 开销直接涨 20-30%
2. **IOKit IOReport**：苹果官方的监控 API，类似「推送通知」，有变化才告诉你，不用你一直问
3. **更少的轮询**：不是所有指标都需要 3 秒刷新一次

---

## 二、具体优化方案

### 优化 1：编译 arm64 原生版本（最简单，收益最大）

**做什么**：让 App 以 arm64 原生运行，不走 Rosetta 转译。

**怎么做**：
```bash
# build-app.sh 添加 --arch 参数
swift build -c release --arch arm64
```

**效果**：
- CPU 占用直接降 20-30%（从 3.58% → 约 2.8%）
- 内存占用也会略降
- 启动速度更快

**风险**：Intel Mac 无法运行（但你的用户大概率是 Apple Silicon）

---

### 优化 2：温度采集降频（简单，收益中等）

**做什么**：温度从 3 秒一次改成 15 秒一次。

**为什么可以**：温度变化很慢，15 秒刷新一次用户完全感觉不到区别。你手机看天气也是几分钟更新一次，没人觉得慢。

**怎么做**：
```swift
// SystemMonitor.swift
// 原来：timer = Timer.scheduledTimer(withTimeInterval: 3.0, ...)
// 改成：timer = Timer.scheduledTimer(withTimeInterval: 15.0, ...)

// 但 CPU/内存/网速还是 3 秒，温度单独 15 秒
```

**效果**：
- SMC 读取次数减少 80%（从每分钟 20 次 → 4 次）
- CPU 降低约 0.3-0.5%

---

### 优化 3：GPU 采集降频（简单，收益中等）

**做什么**：GPU 使用率从 6 秒一次改成 30 秒一次。

**为什么可以**：GPU 使用率变化比 CPU 慢，而且用户主要看的是 CPU 和网速。

**怎么做**：
```swift
// SystemMonitor.swift
// 原来：tickCount % 2 == 0（每 6 秒读一次 GPU）
// 改成：tickCount % 10 == 0（每 30 秒读一次 GPU）
```

**效果**：
- IOAccelerator 调用减少 80%
- CPU 降低约 0.2-0.3%

---

### 优化 4：进程列表降频（简单，收益中等）

**做什么**：进程列表从 3 秒一次改成 5 秒一次。

**为什么可以**：进程列表（谁在用 CPU/内存）变化不频繁，5 秒刷新一次足够。

**怎么做**：
```swift
// SystemMonitor.swift tick() 里
// 原来：每 3 秒调 processMonitor.tick()
// 改成：每 5 秒调一次（tickCount % 2 == 0）
```

**效果**：
- proc_listallpids() 减少 40%
- CPU 降低约 0.2-0.4%

---

### 优化 5：网速采集优化（中等难度，收益中等）

**做什么**：用 IOKit IOReport 替代 getifaddrs 轮询。

**为什么可以**：
- `getifaddrs` 每次要遍历所有网卡，查内核拿字节数
- IOReport 是苹果官方的「推送式」API，网卡有变化才通知你

**怎么做**：
```swift
// 用 IOReportCopyChannelsInGroup("Network", ...) 
// 创建 IOReportSubscription
// 每次回调时读取变化量，而不是主动轮询
```

**效果**：
- 网速采集从「每 3 秒主动问」变成「有变化才告诉你」
- CPU 降低约 0.3-0.5%

**注意**：这个改动较大，需要重写 NetworkMonitorEngine

---

### 优化 6：CPU/GPU 使用率用 IOReport（最难，收益最大）

**做什么**：用 IOReport 替代 host_processor_info 读 CPU 使用率。

**为什么可以**：
- `host_processor_info` 每次要内核拷贝整个 CPU tick 数组
- IOReport 只返回变化量，开销小得多

**怎么做**：
```swift
// IOReportCopyChannelsInGroup("CPU Usage", ...)
// 订阅变化，只在 UI 可见时采集
```

**效果**：
- CPU 降低约 0.5-1.0%（这是 Stats CPU 低的主要原因）

**注意**：这是最难的改动，需要深入理解 IOKit

---

## 三、优化顺序建议

| 优先级 | 优化项 | 难度 | 预期收益 | 建议 |
|--------|--------|------|----------|------|
| P0 | arm64 原生编译 | 简单 | 0.8-1.0% | 立即做 |
| P1 | 温度降频 3s→15s | 简单 | 0.3-0.5% | 立即做 |
| P1 | GPU 降频 6s→30s | 简单 | 0.2-0.3% | 立即做 |
| P1 | 进程降频 3s→5s | 简单 | 0.2-0.4% | 立即做 |
| P2 | 网速用 IOReport | 中等 | 0.3-0.5% | 后续做 |
| P3 | CPU/GPU 用 IOReport | 困难 | 0.5-1.0% | 后续做 |

**预期效果**：
- P0+P1 做完：3.58% → 约 2.2%（已经很接近 Stats）
- 全部做完：3.58% → 约 1.5%（超越 Stats）

---

## 四、测试验证

```bash
# 优化前后对比
scripts/compare-benchmark.sh

# 关注指标
- CPU avg（主要）
- 启动时间
- 内存占用
```
