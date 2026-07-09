# NetMonitor

> **声明**：本项目完全由 AI（Claude）辅助开发，作者完全不懂编程，代码质量可能不够专业。项目仅供个人学习和使用，欢迎提供建议，但请理解代码可能存在不足之处。

macOS 菜单栏网络监控应用，实时显示网速、CPU/GPU/内存使用率、温度、进程流量、流量历史统计（日/周/年视图）、数据导出。

## 关于本项目

这是一个个人学习项目，主要用于：
- 学习 macOS 应用开发
- 了解 Swift 和 SwiftUI
- 探索 AI 辅助编程的可能性

代码由 AI 生成和优化，作者负责需求提出和测试验证。如果您发现任何问题或有改进建议，欢迎提出 Issue 或 Pull Request。

## 功能

### 核心监控
- **实时网速** — 系统级下载/上传速度，菜单栏常驻显示，EMA 平滑
- **进程流量** — 按进程显示网络活动，支持 CPU/内存/网络三模式排序，进程启动时间去重防 PID 复用脏数据
- **系统资源** — CPU / GPU / 内存使用率实时图表，双系列折线（使用率+温度）
- **温度监控** — SMC 直读 CPU/GPU/内存温度（Intel + Apple Silicon），估算值兜底

### 流量统计页（独立窗口 1320×600，隐藏标题栏）
- **日视图** — 24 小时柱状图（本地时区），实时小时缺口补齐，日期下拉选择器
- **周视图** — 从最早数据所在周的周一开始 24 天，双行标签（周几 + MM/DD），今日桶实时更新
- **年视图** — 从当年 1 月开始 24 个月，双行标签（X月 + 年份），当月实时补齐
- **统计栏** — 总下载、总上传、峰值↓、峰值↑（含峰值发生时间）
- **共享 Y 轴最大值** — 下载/上传图表对齐，未来时段灰色 3px 细条

### 数据持久化与导出
- **SQLite** — 分钟级保留 30 天，小时级保留 730 天（支撑年视图）
- **导出** — 日汇总/分钟明细/进程记录 → CSV（CSV/JSON + UTF-8 BOM） → ZIP 打包 → Finder 定位
- **诊断导出** — 事件日志、今日流量、最近 7 天、版本/系统信息 → JSON

### 界面与交互
- **菜单栏弹窗** — 400×自适应，可拖拽、置顶、关闭按钮、内容尺寸自适应
- **菜单栏自定义** — 5 项可拖拽排序、显隐切换、实时预览行（图标+占位文本等宽分布）
- **浮动窗口** — 可拖动、置顶、右键菜单（设置/关闭）、双击动作可选（打开设置/流量统计）
- **深色/浅色模式** — 统一 `#1a1a1e` 背色，所有图表 Canvas 内解析主题色即时生效
- **快捷键** — `Cmd+Shift+N` 切面板、`Cmd+,` 设置、`Cmd+T` 流量统计
- **辅助功能** — 菜单栏项/浮窗/进程行均有 `accessibilityLabel/Value/Children`

### 进程监控增强
- **打开活动监视器** — 进程区标题栏按钮一键跳转
- **四模式排序** — `ForEach(ProcessSortMode.allCases)` 消除重复代码
- **自身行高亮** — NetMonitor 进程单独分组，浅绿背景

## 截图

> 截图待补充

## 系统要求

- macOS 14.0+
- Intel Mac (x86_64) 或 Apple Silicon
- Xcode Command Line Tools
- Homebrew (sqlite3，仅源码构建需要)

## 安装

### 从 Release 下载（推荐）
1. 前往 [Releases](https://github.com/anomalyco/NetworkMonitor/releases)
2. 下载最新的 `NetworkMonitor.dmg` 或 `NetworkMonitor-universal.zip`
3. 打开 DMG，拖拽到 `/Applications`
4. 首次运行右键「打开」绕过 Gatekeeper

### 从源码构建

```bash
git clone https://github.com/anomalyco/NetworkMonitor.git
cd NetworkMonitor

# Debug 构建
swift build

# Release 构建 + 打包 .app
bash build-app.sh --release
open .build/release/NetworkMonitor.app

# 通用二进制（arm64 + x86_64）
bash build-app.sh --release --arch
```

### 运行测试

```bash
export PKG_CONFIG_PATH="$(brew --prefix sqlite)/lib/pkgconfig:$PKG_CONFIG_PATH"
swift test

# 线程检测
swift test --sanitize=thread
```

## 架构

```
Package.swift
├── NetworkMonitorCore/           — 纯数据层（无 SwiftUI）
│   ├── NetworkMonitorEngine.swift   系统网速（sysctl getifaddrs, 3s tick, EMA 平滑）
│   ├── SystemMonitor.swift          CPU/内存/GPU 采样（host_processor_info + IOAccelerator）
│   ├── ThermalMonitor.swift         SMC 温度读取（IOConnectCallStructMethod, Intel+AS）
│   ├── DatabaseManager.swift        SQLite 流量存储（15s 刷盘, os_log 错误日志）
│   ├── AppSettings.swift            设置管理（@Published + UserDefaults + didSet）
│   ├── SpeedFormatter.swift         格式化工具 + currentDateStamp
│   ├── L10n.swift                   中英文国际化
│   ├── ChartCalc.swift              图表计算辅助
│   ├── VisibilityHelper.swift       进程可见性检测
│   ├── ProcessMonitor.swift         进程 CPU/内存/网络（proc_listallpids + nettop CSV 解析）
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
│   ├── BarChartView.swift           柱状图渲染
│   ├── TrafficStatsView.swift       流量统计主视图
│   ├── ExportDataSheet.swift        导出数据弹窗
│   ├── PermissionsView.swift        权限页（占位，待 TCC 接入）
│   └── ThinScroller.swift           自定义滚动条
│
└── NetworkMonitorTests/          — 91 个单元测试
    ├── NetworkMonitorEngineTests.swift
    ├── SystemMonitorTests.swift
    ├── ThermalMonitorTests.swift
    ├── DatabaseManagerTests.swift     — @Suite(.serialized), 内存 SQLite
    ├── GPUInfoTests.swift
    ├── SpeedFormatterTests.swift
    ├── ChartLogicTests.swift
    ├── VisibilityHelperTests.swift
    ├── L10nTests.swift
    ├── AppSettingsTests.swift         — @Suite(.serialized), UUID UserDefaults suite
    └── ProcessMonitorTests.swift
```

## 技术栈

- **语言**: Swift 5.9
- **框架**: SwiftUI + AppKit (NSVisualEffectView, NSPanel)
- **数据**: IOKit, SQLite3 (C API), sysctl, proc_pidinfo, nettop
- **最低系统**: macOS 14+
- **包管理**: Swift Package Manager
- **CI**: GitHub Actions (lint, test, thread-sanitizer, release build, universal binary, format check, quality script)

## 权限

| 权限 | 用途 |
|------|------|
| 网络监控 | 通过 `getifaddrs` 读取系统网络接口字节统计 |
| 进程监控 | 通过 `nettop` 子进程获取按进程流量（可选） |
| 温度读取 | 通过 `IOConnectCallStructMethod` 读取 SMC 传感器 |
| 辅助功能 | 浮动窗口置顶/点击穿透（需在系统设置授权） |

所有数据只读，不修改系统设置，不上传任何数据。

## 已知限制

- 首次启动温度显示需要约 9 秒（SMC 轮询机制）
- 部分虚拟网络接口（en5-en9）默认排除以避免重复计数，可在设置中自定义前缀
- 进程网络采集依赖 `nettop` 输出格式，macOS 版本升级可能需要调整解析
- 无自动更新检查，需手动下载新版本
- 权限页目前为占位，TCC 授权检测待实现

## Contributing

欢迎贡献！请阅读 [Contributing Guide](CONTRIBUTING.md)。

## License

[MIT](LICENSE)