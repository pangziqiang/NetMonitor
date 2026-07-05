#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="NetworkMonitor"

echo "🔨 Building $APP_NAME..."
swift build

echo "✅ Build complete"
echo "Run with: ./run.sh"