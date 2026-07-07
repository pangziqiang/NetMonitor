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


