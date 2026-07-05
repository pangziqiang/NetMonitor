#!/bin/bash
# 创建 DMG 安装包
# 用法: ./create-dmg.sh [--release]

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="NetworkMonitor"
DMG_NAME="${APP_NAME}.dmg"
VOLUME_NAME="${APP_NAME} Installer"
DMG_PATH="${PROJECT_DIR}/${DMG_NAME}"

# 检查应用是否存在
APP_PATH="${PROJECT_DIR}/.build/release/${APP_NAME}.app"
if [ ! -d "$APP_PATH" ]; then
    echo "❌ 应用不存在: $APP_PATH"
    echo "请先运行: ./build-app.sh --release"
    exit 1
fi

# 清理旧的 DMG
rm -f "$DMG_PATH"

# 创建临时目录
TEMP_DIR=$(mktemp -d)
TEMP_APP="${TEMP_DIR}/${APP_NAME}.app"
TEMP_LINK="${TEMP_DIR}/Applications"

echo "📦 创建 DMG 安装包..."

# 复制应用到临时目录
cp -R "$APP_PATH" "$TEMP_APP"

# 创建 Applications 快捷方式
ln -s /Applications "$TEMP_LINK"

# 创建 DMG
hdiutil create \
    -volname "$VOLUME_NAME" \
    -srcfolder "$TEMP_DIR" \
    -ov \
    -format UDZO \
    -imagekey zlib-level=9 \
    "$DMG_PATH"

# 清理临时目录
rm -rf "$TEMP_DIR"

# 验证 DMG
if [ -f "$DMG_PATH" ]; then
    echo "✅ DMG 创建成功: $DMG_PATH"
    echo "📊 文件大小: $(du -h "$DMG_PATH" | cut -f1)"
    echo ""
    echo "使用方法:"
    echo "1. 双击打开 ${DMG_NAME}"
    echo "2. 将 ${APP_NAME}.app 拖动到 Applications 文件夹"
    echo "3. 从 Applications 启动应用"
else
    echo "❌ DMG 创建失败"
    exit 1
fi
