#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="NetworkMonitor"

# Parse arguments
BUILD_TYPE="debug"
INSTALL=false
RUN=true
for arg in "$@"; do
    case $arg in
        --release|-r) BUILD_TYPE="release" ;;
        --install) INSTALL=true ;;
        --no-run) RUN=false ;;
        --help|-h)
            echo "Usage: $0 [--release|-r] [--install] [--no-run]"
            echo "  Default: debug build, no install, auto-run"
            echo "  --release, -r: release build"
            echo "  --install: copy to /Applications"
            echo "  --no-run: do not kill/launch the app"
            exit 0
            ;;
    esac
done

if [ "$BUILD_TYPE" = "release" ]; then
    BUILD_DIR="$PROJECT_DIR/.build/release"
    echo "🔨 Building $APP_NAME (release)..."
    swift build -c release
else
    BUILD_DIR="$PROJECT_DIR/.build/debug"
    echo "🔨 Building $APP_NAME (debug)..."
    swift build
fi

APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"

echo "📦 Creating .app bundle..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"

cp "$BUILD_DIR/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/"

# Copy icon
if [ -f "$PROJECT_DIR/AppIcon.icns" ]; then
    cp "$PROJECT_DIR/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/"
elif [ -f "$PROJECT_DIR/Sources/NetworkMonitor/AppIcon.icns" ]; then
    cp "$PROJECT_DIR/Sources/NetworkMonitor/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/"
fi

cp "$PROJECT_DIR/Resources/Info.plist" "$APP_BUNDLE/Contents/Info.plist"

# Also update root-level .app so Finder always sees the latest
rm -rf "$PROJECT_DIR/$APP_NAME.app"
cp -R "$APP_BUNDLE" "$PROJECT_DIR/$APP_NAME.app"

# Install to /Applications if requested
if [ "$INSTALL" = true ]; then
    if [ -d "/Applications/$APP_NAME.app" ]; then
        rm -rf "/Applications/$APP_NAME.app"
    fi
    cp -R "$APP_BUNDLE" "/Applications/$APP_NAME.app"
    echo "📦 Installed to /Applications/$APP_NAME.app"
fi

echo "✅ Done: $APP_BUNDLE"
if [ "$RUN" = true ]; then
    echo "🚀 Killing old instance..."
    killall "$APP_NAME" 2>/dev/null || true
    sleep 0.5
    echo "🚀 Launching..."
    open "$APP_BUNDLE"
fi