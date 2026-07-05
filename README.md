# NetMonitor

> **声明**：本项目完全由 AI（Claude）辅助开发，作者完全不懂编程，代码质量可能不够专业。项目仅供个人学习和使用，欢迎提供建议，但请理解代码可能存在不足之处。

macOS 菜单栏网络监控应用，实时显示网速、CPU/GPU/内存使用率、温度和进程流量。

## 关于本项目

这是一个个人学习项目，主要用于：
- 学习 macOS 应用开发
- 了解 Swift 和 SwiftUI
- 探索 AI 辅助编程的可能性

代码由 AI 生成和优化，作者负责需求提出和测试验证。如果您发现任何问题或有改进建议，欢迎提出 Issue 或 Pull Request。

## 功能

- **实时网速** — 系统级下载/上传速度，菜单栏常驻显示
- **进程流量** — 按进程显示网络活动，支持排序和详情查看
- **系统资源** — CPU / GPU / 内存使用率实时图表
- **温度监控** — SMC 直读 CPU/GPU/内存温度（Intel + Apple Silicon）
- **流量历史** — 7 天日级 + 分钟级流量统计，SQLite 持久化
- **深色/浅色模式** — 自适应系统外观

## 截图

> 截图待补充

## 系统要求

- macOS 14.0+
- Intel Mac (x86_64) 或 Apple Silicon
- Xcode Command Line Tools
- Homebrew (sqlite3)

## 安装

### 从源码构建

```bash
git clone https://github.com/anomalyco/NetworkMonitor.git
cd NetworkMonitor

# Debug 构建
swift build

# Release 构建 + 打包 .app
bash build-app.sh --release
open .build/release/NetworkMonitor.app
```

### 运行测试

```bash
export PKG_CONFIG_PATH="$(brew --prefix sqlite)/lib/pkgconfig:$PKG_CONFIG_PATH"
swift test
```

## 架构

```
Package.swift
├── NetworkMonitorCore/           — 纯数据层（无 SwiftUI）
│   ├── NetworkMonitorEngine.swift   系统网速（sysctl getifaddrs, 3s tick, EMA 平滑）
│   ├── SystemMonitor.swift          CPU/内存/GPU 采样（host_processor_info + IOAccelerator）
│   ├── ThermalMonitor.swift         SMC 温度读取（IOConnectCallStructMethod, Intel+AS）
│   ├── DatabaseManager.swift        SQLite 流量存储（60s 刷盘, os_log 错误日志）
│   ├── AppSettings.swift            设置管理（@Published + UserDefaults + didSet）
│   ├── SpeedFormatter.swift         格式化工具 + currentDateStamp
│   ├── L10n.swift                   中英文国际化
│   ├── ChartCalc.swift              图表计算辅助
│   ├── VisibilityHelper.swift       进程可见性检测
│   └── AppConstants.swift           常量定义（Bundle ID + OSLog subsystem）
│
├── NetworkMonitor/               — UI 层（SwiftUI + AppKit）
│   ├── NetworkMonitorApp.swift      @main, AppDelegate, 窗口场景
│   ├── MenuBarPopover.swift         弹出窗主体 + MiniSparkLine（CGContext crosshair）
│   ├── StatusItemManager.swift      菜单栏图标 + MenuBarPanel + StatusBarView
│   ├── SettingsView.swift           设置页（通用/流量统计/权限）+ a11y labels
│   ├── AppSettings+UI.swift         AppSettings UI 扩展（菜单项标签/图标/绑定）
│   ├── AppTheme.swift               颜色系统 + 卡片样式
│   ├── ChartView.swift              CGContext 图表引擎 + hoverFingerprint
│   ├── SystemChartView.swift        双系列折线图
│   ├── FloatingWindowManager.swift  浮窗管理
│   ├── GraphDetailView.swift        流量图表详情
│   ├── SystemGraphDetailView.swift  系统资源图表详情
│   ├── PopoverManager.swift         弹窗状态管理
│   ├── AppState.swift               全局状态
│   └── ThinScroller.swift           自定义滚动条
│
└── NetworkMonitorTests/          — 69 个单元测试
    ├── NetworkMonitorEngineTests.swift
    ├── SystemMonitorTests.swift
    ├── ThermalMonitorTests.swift
    ├── DatabaseManagerTests.swift     — @Suite(.serialized), 内存 SQLite
    ├── GPUInfoTests.swift
    ├── SpeedFormatterTests.swift
    ├── ChartLogicTests.swift
    ├── VisibilityHelperTests.swift
    ├── L10nTests.swift
    └── AppSettingsTests.swift         — @Suite(.serialized), UUID UserDefaults suite
```

## 技术栈

- **语言**: Swift 5.9
- **框架**: SwiftUI + AppKit (NSVisualEffectView, NSPanel)
- **数据**: IOKit, SQLite3 (C API), sysctl
- **最低系统**: macOS 14+
- **包管理**: Swift Package Manager
- **CI**: GitHub Actions

## 权限

| 权限 | 用途 |
|------|------|
| 网络监控 | 通过 `getifaddrs` 读取系统网络接口字节统计 |
| 进程监控 | 通过 `nettop` 子进程获取按进程流量（可选） |
| 温度读取 | 通过 `IOConnectCallStructMethod` 读取 SMC 传感器 |

所有数据只读，不修改系统设置，不上传任何数据。

## 已知限制

- 首次启动温度显示需要约 9 秒（SMC 轮询机制）
- 部分虚拟网络接口（en5-en9）被排除以避免重复计数

## Contributing

欢迎贡献！请阅读 [Contributing Guide](CONTRIBUTING.md)。

## License

[MIT](LICENSE)
