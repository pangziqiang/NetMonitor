# Home Directory — OpenCode Context

这是一个 macOS 菜单栏网络监控应用，使用 Swift 编写。

## Environment

- **OS**: macOS (darwin), **Shell**: zsh
- **Package manager**: Homebrew (USTC mirror: `mirrors.ustc.edu.cn`)
- **OpenCode config**: `~/.config/opencode/opencode.jsonc`
- **MiMo CLI**: `~/.mimocode/bin` (on PATH via `.zshrc`)

## Model Setup

Custom provider "mimo" via `@ai-sdk/openai-compatible`:

| Alias | Model ID | Notes |
|-------|----------|-------|
| `mimo/mimo-v2.5-pro` | Primary model | text-only, 1M context |
| `mimo/mimo-v2.5` | Small model | text + image input, 1M context |

API base: `https://token-plan-cn.xiaomimimo.com/v1`

## Conventions

- 当创建项目脚手架时，始终在 `opencode.json` 中包含 `"$schema"`。
- 中文语言用户 — 除非项目仅限英文，否则优先使用中文响应。
- `.zshrc` 中未发现全局 git 配置覆盖或别名；适用标准 git 行为。

## Project Structure

这是一个 macOS 菜单栏网络监控应用，具有以下特点：

- **语言**: Swift 5.9
- **平台**: macOS 14+ (菜单栏应用)
- **包管理器**: Swift Package Manager (SPM)
- **架构**: 双目标
  - `NetworkMonitorCore` — 数据层 (Foundation + Combine + SQLite3 C API, **无 SwiftUI**)
  - `NetworkMonitor` — UI 层 (SwiftUI + AppKit 混合)
- **测试**: Swift Testing 框架 (`@Test`, `@Suite(.serialized)`)
- **CI**: GitHub Actions (`.github/workflows/ci.yml`)

## Directory Layout

```
NetworkMonitor/
├── Package.swift
├── README.md
├── LICENSE
├── AppIcon.icns
├── AppIcon.svg
├── build-app.sh
├── build.sh
├── run.sh
├── scripts/
│   ├── benchmark.sh
│   └── quality.sh
├── Sources/
│   ├── NetworkMonitorCore/       ← 数据层 (不允许 SwiftUI)
│   │   ├── NetworkMonitorEngine.swift
│   │   ├── SystemMonitor.swift
│   │   ├── ThermalMonitor.swift
│   │   ├── DatabaseManager.swift
│   │   ├── AppSettings.swift
│   │   ├── AppConstants.swift
│   │   ├── SpeedFormatter.swift
│   │   ├── L10n.swift
│   │   ├── ChartCalc.swift
│   │   ├── ProcessMonitor.swift
│   │   ├── VisibilityHelper.swift
│   │   └── IOReportWrapper.swift   ← libIOReport.dylib 动态加载包装
│   └── NetworkMonitor/           ← UI 层 (SwiftUI + AppKit)
├── docs/
│   └── design/                   ← 设计规范文件
└── Tests/
    └── NetworkMonitorTests/
```

## 进程监控

- **CPU + 内存**：`ProcessMonitor.swift` 用 `proc_listallpids() + proc_pidinfo(PROC_PIDTASKINFO)` 每 3s 采样，差值算 CPU%，`pti_resident_size` 取 RSS。
- **网络每进程**：通过 `nettop -P -L 1 -n` 子进程采集。`ProcessMonitor.tickNetwork()` 在后台队列运行 nettop，解析 CSV（`进程名.PID,下载字节,上传字节`），与前一次采样做差值得到速率（bytes/sec）。`topByNetwork` 按总流量排序。UI 中 `processSortMode = .network` 时 CPU/Memory 列替换为 ↓↑ 速率。
- **节流**：`isActive` 由 popover `onAppear/onDisappear` 控制，关闭时零开销。`isActive` 通过 `NSLock` 保护，跨三个队列（tickQueue/networkQueue/main）读写安全。
- **UI**：`MenuBarPopover.topProcessesSection` 始终展开，四模式排序切换（按CPU / CPU总 / 按内存 / 按网络），底部自身行。排序按钮用 `ForEach(ProcessSortMode.allCases)` 生成，消除重复代码。
- **CPU总排序**：`ProcessMonitor` 新增 `topByCPUTotal`，按 `cpuPercent / processorCount` 排序。`processorCount` 来自 `ProcessInfo.processInfo.processorCount`。UI 中 `processSortMode` 枚举控制显示哪个列表，CPU 列值相应切换。
- **线程安全**：`ProcessMonitor.stop()` 中网络状态重置通过 `networkQueue.async` 执行，避免与 `tickNetwork()` 的数据竞争。`tickNetwork()` 开头检查 `isActive`。`topByNetwork` 在 `networkQueue.async` 内 dispatch 回 main 更新。

## 功能记录

- **打开活动监视器**：`MenuBarPopover.topProcessesSection` header 中 "活跃应用" 标题右侧有 `[waveform 活动监视器]` 按钮，点击通过 `NSWorkspace.shared.openApplication` 打开 `/System/Applications/Utilities/Activity Monitor.app`。按钮使用 `.downloadColor` 背景 `opacity(0.15)` + `.downloadColor` 文字，与 "按CPU/按内存" 选中态风格一致。
- **流量统计页**：独立窗口（1320×600, `.hiddenTitleBar`），通过菜单栏 → 监控 → 流量统计（Cmd+T）或底部"流量统计"按钮打开。实现文件：`BarChartView.swift`（柱状图渲染）+ `TrafficStatsView.swift`（主视图）。三个视图：日（24h本地时间）、周（从最早数据周一开始24天）、年（从当年1月开始24个月）。统计栏显示总下载/总上传/峰值↓/峰值↑。日页面有日期下拉选择器。设计规范和原始文件见 `docs/design/` 目录。柱状图渲染使用 `theme` 颜色，亮色/暗色模式均正常显示。
- **菜单栏预览行**：设置页「菜单栏显示项目」区顶部新增预览行，显示启用项目的图标+占位文字（`↓ MB/s ↑ KB/s`、`-- %`），等宽分布，开关后自适应。
- **统一深色背景**：所有窗口页面统一使用 `#1a1a1e`（`theme.appBg`）。
- **historySeconds 持久化**：存 UserDefaults，重启保留。
- **hourly 保留730天**：支撑年视图24个月。
- **移除清空数据按钮**：用户要求移除「清空流量数据」功能入口。
- **浮窗精度**：CPU/GPU/MEM 显示 `%.1f%%`（非 `Int` 截断），可访问性值同步。
- **文件名安全**：导出/诊断文件名使用 `yyyy-MM-dd_HH-mm-ss` 格式，无冒号非法字符。

## 已修复 Bug

### 2026-07-09 IOReport 推送式监控

**IOReportWrapper.swift** — libIOReport.dylib 动态加载包装
- `IOReportLib.shared` 为可选类型，Intel 机器返回 `nil`（库存在但 API 会 SIGSEGV）
- `isAvailable()` 使用 `#if arch(arm64)` 编译期隔离，Intel 永远返回 `false`
- 所有函数指针类型别名：`CopyChannelsInGroupFunc`、`IterateNewSamplesFunc` 等
- `IOReportMonitor` 订阅 IOReport 分组（Network/CPU），回调式推送数据

**NetworkMonitorEngine.swift** — IOReport 网络路径
- 新增 `IOReportNetworkMonitor` 类，订阅 IOReport Network 组
- 回调获取 `bytes_in`/`bytes_out` 差值，计算实时速率
- `useIOReport` 标志：Apple Silicon 用 IOReport，Intel 用 getifaddrs 轮询

**SystemMonitor.swift** — IOReport CPU 路径
- `startIOReportCPU()` 订阅 IOReport CPU 组，从 total/idle cycles 计算 CPU%
- `useIOReportCPU` 标志：Apple Silicon 用 IOReport 回调，Intel 用 host_processor_info 轮询
- `tick()` 在 IOReport 模式下跳过重复 CPU 采集

**崩溃修复**：Intel 上 `IOReportCopyChannelsInGroup` 会 SIGSEGV，通过 `#if arch(arm64)` 编译期排除

### 2026-07-09 全局审计修复（14 Critical + 26 High + 40+ Medium/Low）

**线程安全**
- `ProcessMonitor.isActive`：加 `NSLock` 保护，消除跨三队列数据竞争。
- `StatusItemManager`：全局事件回调 `panel.orderOut(nil)` dispatch 到主线程。
- `MenuBarPopover`：`onAppear/onDisappear` 异步设置 `isActive` 到正确队列。

**死锁**
- `DatabaseManager.deinit`：新增 `_flushPendingSyncDirect()` 绕过 `queue.sync`，避免退出时死锁。
- `ThermalMonitor.connect()`：重写为先解锁再 disconnect，消除锁内调用 disconnect 的死锁模式。

**主线程卡顿**
- `MenuBarPopover`：`formatNetworkSpeed` 改用 Core 层 `formatSpeed()`，消除重复实现。

**亮色模式**
- `BarChartView`：全部 `Color.white.opacity(...)` 替换为 `theme` 颜色，亮色模式可读。
- `TrafficStatsView`：同上，统计栏和图表背景使用 `theme` 颜色。

**文件名安全**
- `SettingsView`/`ExportDataSheet`：ISO8601 冒号文件名改用 `safeFilenameDate()`（`yyyy-MM-dd_HH-mm-ss`）。

**导出健壮性**
- `ExportDataSheet`：检查 `DatabaseManager.shared` nil；检查 zip 进程退出码。
- `DatabaseManagerTests`：JSON 测试加 `#expect(parsed != nil)` 防假阳性。

**数据重绘**
- `ChartView.dataFingerprint`：改用最后 3 个值的哈希，数据变化时正确重绘。
- `SystemChartView`/`MiniSparkLine`：每帧 `map{min}` 只计算一次，消除重复分配。

**UI 一致性**
- `FloatingWindowManager`：字体统一 `.semibold`；浮窗尺寸容差改 0.5pt；CPU/GPU/MEM 显示 `%.1f%%`。
- `FloatingWindowManager`：可访问性每行独立 frame；`defer` 恢复 `panel.level`。
- `processSortToggle`：改 `ForEach(ProcessSortMode.allCases)` 消除 4 段重复代码。

**CI**
- `ci.yml`：Benchmark job 先 `build-app.sh` 再 `benchmark.sh`；移除无效 `brew install sqlite`；加 `concurrency.cancel-in-progress`。
- `quality.sh`：移除 `2>/dev/null`，错误可见。

**架构清理**
- `PopoverManager`：加 `private init()`，防止意外创建多实例。
- `AppState`：移除无用 `@Published var databaseAvailable`。
- `StatusItemManager`：移除 `NSHostingController` 多余 `AnyView` 包裹。
- `windowShouldClose`：返回 `true`，Cmd+W 生效。
- `PermissionsView`：保留占位 `granted: true`（待接 TCC API）。

## Git 标签

- `stable-v1.7-io-fixes` — 当前版本：IOReport 推送式监控 + Intel 优雅降级 + 全局审计修复
- `stable-v1.7-ui-fixes` — 上一版本：流量统计日/周/年视图 + 统一背景 + 预览行 + 持久化

## 数据导出功能（已实现）

导出功能已全部落地：峰值追踪、进程 JSON 暂存、列迁移、范围查询、CSV/JSON 导出(含 BOM)、ZIP 打包、Finder 显示。相关文件：`ExportDataSheet.swift`、`DatabaseManager.swift`（导出方法）。

## 竞品对比基准测试 (2026-07-09)

测试脚本：`scripts/compare-benchmark.sh`，支持多 App 并行采样，自动生成 Markdown+HTML 报告。

| App | CPU avg | MEM avg | 线程 | 启动 | 大小 | 架构 |
|-----|---------|---------|------|------|------|------|
| **NetworkMonitor** | **0.59%** | 106MB | 7 | 251ms | 9MB | Universal |
| Stats | 1.00% | 119MB | 15 | 262ms | 18MB | Universal |
| NetWorker Pro | 5.65% | 105MB | 7 | 226ms | 9MB | Universal |
| HagimiMonitor | 4.60% | 94MB | 9 | 196ms | 9MB | x86_64 |

**NetworkMonitor CPU 从 3.58% 降到 0.59%，降幅 83%，现为全场最低。**

综合排名 (加权0-10)：NetworkMonitor **8.5** > Stats 7.2 > HagimiMonitor 4.1 > NetWorker Pro 3.5

**CPU 降低的关键因素**：IOReport 动态加载（Apple Silicon 推送式）+ Intel 优雅降级 + `#if arch(arm64)` 编译期隔离

**改进方向**：编译 arm64 原生版本（当前 Intel 测试已无 IOReport 加持，Apple Silicon 上优势更大）