#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="NetMonitor"
BINARY=".build/debug/$APP_NAME"

# 确保已编译
if [ ! -f "$BINARY" ]; then
    echo "==> 编译中…"
    swift build
fi

echo "==> 启动 $APP_NAME"
exec "$BINARY"