# Contributing to NetMonitor

感谢您对 NetMonitor 的关注！

> **说明**：本项目由 AI 辅助开发，作者完全不懂编程。如果您有更好的实现方式或发现代码问题，非常欢迎提出改进建议。

欢迎贡献代码、报告问题或提出建议。

## 如何贡献

### 报告问题

1. 在 [GitHub Issues](https://github.com/anomalyco/NetworkMonitor/issues) 中搜索是否已有相同问题
2. 如果没有，创建新的 Issue，包含：
   - 问题描述
   - 复现步骤
   - 预期行为 vs 实际行为
   - 系统版本和应用版本
   - 截图（如适用）

### 提交代码

1. Fork 本仓库
2. 创建您的特性分支：`git checkout -b feature/amazing-feature`
3. 提交您的更改：`git commit -m 'Add amazing feature'`
4. 推送到分支：`git push origin feature/amazing-feature`
5. 创建 Pull Request

### 代码规范

- 使用 Swift 5.9+ 语法
- 遵循项目现有的代码风格
- Core 层不引入 SwiftUI/AppKit
- UI 层使用 SwiftUI + AppKit 混合
- 使用 os_log 进行日志记录（不要使用 print）
- 为新功能添加单元测试

### 提交信息规范

使用清晰的提交信息：

```
<类型>: <简短描述>

<详细描述（可选）>
```

类型包括：
- `feat`: 新功能
- `fix`: Bug 修复
- `docs`: 文档更新
- `style`: 代码格式调整
- `refactor`: 重构
- `test`: 测试相关
- `chore`: 构建/工具相关

### 开发环境

1. macOS 14.0+
2. Xcode 15.0+ 或 Xcode Command Line Tools
3. Homebrew（用于安装 sqlite3）

```bash
# 克隆仓库
git clone https://github.com/anomalyco/NetworkMonitor.git
cd NetworkMonitor

# 安装依赖
brew install sqlite

# 构建
swift build

# 运行测试
swift test

# 构建 .app
bash build-app.sh --release
```

### 测试

- 所有测试必须通过：`swift test`
- 新功能应包含单元测试
- 测试使用 Swift Testing 框架（`@Test`, `@Suite`）

## 行为准则

- 尊重所有参与者
- 接受建设性批评
- 专注于对社区最有利的事情
- 对他人表示同理心

## 许可证

通过贡献代码，您同意您的贡献将在 [MIT 许可证](LICENSE) 下授权。

## 联系方式

如有疑问，请通过 GitHub Issues 联系。
