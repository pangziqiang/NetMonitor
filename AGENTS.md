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

