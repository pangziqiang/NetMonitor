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
│   │   └── VisibilityHelper.swift
│   └── NetworkMonitor/           ← UI 层 (SwiftUI + AppKit)
├── docs/
│   └── design/                   ← 设计规范文件
└── Tests/
    └── NetworkMonitorTests/
```

## 浮窗按行双击跳转不同页（方案 B，待实施）

双击浮窗不同行跳转不同设置页：
- 速度/流量行 → `.history`（流量统计页）
- CPU/GPU/内存行 → `.general`（通用页）

实现要点：
1. `FloatingWindowView.mouseDown(with:)` 用 `event.locationInWindow` hit-test 每行的 `NSRect`
2. 行 rect 从 `buildRows()` 行序推算（rowHeight=24, padding=10, y 居中偏移 = (bounds.height - rowCount*24)/2）
3. `onDoubleClick` 改签名为 `((SettingsTab) -> Void)?`，导航侧注入不同 tab
4. `NetworkMonitorApp` 的 `onDoubleClick` 闭包接收 `SettingsTab` 参数设 `appState.settingsTab`

## 进程监控

- **CPU + 内存**：`ProcessMonitor.swift` 用 `proc_listallpids() + proc_pidinfo(PROC_PIDTASKINFO)` 每 3s 采样，差值算 CPU%，`pti_resident_size` 取 RSS。
- **网络每进程**：通过 `nettop -P -L 1 -n` 子进程采集。`ProcessMonitor.tickNetwork()` 在后台队列运行 nettop，解析 CSV（`进程名.PID,下载字节,上传字节`），与前一次采样做差值得到速率（bytes/sec）。`topByNetwork` 按总流量排序。UI 中 `processSortMode = .network` 时 CPU/Memory 列替换为 ↓↑ 速率。
- **节流**：`isActive` 由 popover `onAppear/onDisappear` 控制，关闭时零开销。
- **UI**：`MenuBarPopover.topProcessesSection` 始终展开，四模式排序切换（按CPU / CPU总 / 按内存 / 按网络），底部自身行。
- **CPU总排序**：`ProcessMonitor` 新增 `topByCPUTotal`，按 `cpuPercent / processorCount` 排序。`processorCount` 来自 `ProcessInfo.processInfo.processorCount`。UI 中 `processSortMode` 枚举控制显示哪个列表，CPU 列值相应切换。
- **线程安全**：`ProcessMonitor.stop()` 中网络状态重置通过 `networkQueue.async` 执行，避免与 `tickNetwork()` 的数据竞争。`tickNetwork()` 开头检查 `isActive`。

## 功能记录

- **打开活动监视器**：`MenuBarPopover.topProcessesSection` header 中 "活跃应用" 标题右侧有 `[waveform 活动监视器]` 按钮，点击通过 `NSWorkspace.shared.openApplication` 打开 `/System/Applications/Utilities/Activity Monitor.app`。按钮使用 `.downloadColor` 背景 `opacity(0.15)` + `.downloadColor` 文字，与 "按CPU/按内存" 选中态风格一致。
- **流量统计页**：独立窗口（1320×600, `.hiddenTitleBar`），通过菜单栏 → 监控 → 流量统计（Cmd+T）或底部"流量统计"按钮打开。实现文件：`BarChartView.swift`（柱状图渲染）+ `TrafficStatsView.swift`（主视图）。只有今日视图（24根柱子），统计栏显示总下载/总上传/峰值↓/峰值↑。设计规范和原始文件见 `docs/design/` 目录。

## 已修复 Bug

- `DatabaseManager.deinit`：`flushPendingTrafficSync()` 在 `closed = true` 之前调用，避免退出数据丢失。
- `DatabaseManager.deinit`：`db` 提局部变量再进 `queue.async`，避免 deinit 中闭包强捕获 self 导致 `sqlite3_close` 不执行。
- `SettingsView`：移除 `cachedVisibility` 缓存，每次实时创建 `VisibilityHelper`，避免 `canDisable()` 读到旧快照导致所有可见元素可全关。
- `NetworkMonitorApp`：`onOpenSettings` 闭包不捕获 self（已确认闭包体内无 self 引用）。
- `ProcessMonitor`：`stop()` 中网络状态重置改为 `networkQueue.async` 执行，避免与 `tickNetwork()` 的数据竞争；`tickNetwork()` 开头检查 `isActive`。
- `NetworkMonitorApp`：`onChange(of: historySeconds)` 移除冗余 `max/min` clamp（`AppState` setter 已保证）。
- `MenuBarPopover`：`formatNetworkSpeed` 改用 1024 进制，与 `SpeedFormatter` 一致。
- `FloatingWindowManager`：`NSScreen.main` 为 nil 时加 `os_log` 错误日志。
- `StatusItemManager`：`statusItem?.button` 为 nil 时加 `os_log` 错误日志。

## Git 标签

- `v1.0-snapshot` — 进程监控功能前基线
- `stable-v1.1` — 进程监控 CPU+内存稳定版
- `stable-v1.2-diagnostics` — 日志系统 + 进程数量即时响应 + 双击标题跳转

## 数据导出功能方案（待实施）

### 改动范围

**数据采集层（NetworkMonitorEngine）：**
- tick() 中追踪峰值速度：`peakDown` / `peakUp`（每3秒比较取 max）
- flushMinute() 时写入 DB 并重置峰值

**数据采集层（SystemMonitor）：**
- tick() 中 processMonitor.tick() 后，把 topByNetwork 前3名格式化为 JSON 暂存到 DB
- 格式：`[{"name":"Safari","down":123456,"up":7890}]`

**存储层（DatabaseManager）：**
- `traffic_minutely` 新增 3 列：`peak_down INTEGER DEFAULT 0`, `peak_up INTEGER DEFAULT 0`, `top_processes TEXT DEFAULT NULL`
- 迁移：`ALTER TABLE ADD COLUMN`（安全，现有行填默认值）
- 留存从 7 天 → 30 天（`MINUTELY_RETENTION_DAYS = 30`）
- 新增范围查询：`dailyTraffic(from:to:)`, `minutelyTraffic(from:to:)`
- 新增导出方法：`exportDailyCSV(from:to:)`, `exportMinutelyCSV(from:to:)`
- CSV 文件头加 UTF-8 BOM (`\u{FEFF}`) 防止 Excel 中文乱码

**UI 层（SettingsView）：**
- HistoryView 底部移除「清空数据库」按钮
- HistoryView 表格下方加「导出数据」按钮
- 点击弹出 Sheet 配置面板：
  - 时间范围：最近7天 / 最近30天 / 全部 / 自定义
  - 数据类型：☑ 每日汇总 ☑ 分钟明细 ☑ 进程记录（分钟明细的子选项）
  - 文件格式：CSV / JSON
- 默认：最近7天 + 每日汇总 + CSV（一键导出场景）
- 导出写入 ZIP 包（调系统 `zip` 命令，零依赖）
- 完成后提示 +「在 Finder 中显示」按钮
- 诊断区保留「清空流量数据」按钮（从流量统计tab移过来）

**L10n：** 新增翻译：导出数据、时间范围、数据类型、文件格式等

### 改动文件清单

| 文件 | 改动 |
|------|------|
| `DatabaseManager.swift` | 加列迁移、峰值/进程暂存属性、`_insertMinutely` 改写、留存改30天、范围查询、CSV导出 |
| `NetworkMonitorEngine.swift` | 峰值追踪 + flush 重置 |
| `SystemMonitor.swift` | tick 后暂存进程 JSON |
| `SettingsView.swift` | HistoryView 导出按钮 + Sheet 面板 + 清空按钮移位 |
| `L10n.swift` | 新增翻译 |
| 测试 | 迁移测试、导出测试 |

### 风险点

- ALTER TABLE 迁移失败 → 用 `PRAGMA table_info` 检查列存在性再加
- 进程快照 3s 写内存 → 只更新变量，flush 时才写 DB
- CSV 中文乱码 → 文件头加 BOM
- ZIP 打包 → 用 `Process` 调 `/usr/bin/zip`，需处理失败回退


