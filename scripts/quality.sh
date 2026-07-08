#!/bin/bash
# 代码质量检查脚本
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"

echo "🔍 代码质量检查"
echo "================"

# 1. SwiftLint 检查
echo ""
echo "1. SwiftLint 检查..."
if command -v swiftlint &> /dev/null; then
    swiftlint lint --quiet
    echo "✅ SwiftLint 检查完成"
else
    echo "⚠️  SwiftLint 未安装，跳过检查"
    echo "   安装: brew install swiftlint"
fi

# 2. 编译检查
echo ""
echo "2. 编译检查..."
if swift build; then
    echo "✅ 编译成功"
else
    echo "❌ 编译失败"
    exit 1
fi

# 3. 测试检查
echo ""
echo "3. 测试检查..."
if swift test; then
    echo "✅ 测试通过"
else
    echo "❌ 测试失败"
    exit 1
fi

# 4. 代码统计
echo ""
echo "4. 代码统计..."
SWIFT_FILES=$(find Sources -name "*.swift" | wc -l)
SWIFT_LINES=$(find Sources -name "*.swift" -exec cat {} \; | wc -l)
TEST_FILES=$(find Tests -name "*.swift" | wc -l)
TEST_LINES=$(find Tests -name "*.swift" -exec cat {} \; | wc -l)

echo "   源代码: $SWIFT_FILES 个文件, $SWIFT_LINES 行"
echo "   测试代码: $TEST_FILES 个文件, $TEST_LINES 行"

echo ""
echo "✅ 质量检查完成"