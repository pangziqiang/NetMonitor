#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="NetMonitor"

# Parse arguments
BUILD_TYPE="debug"
INSTALL=false
RUN=true
ARCH=""
for arg in "$@"; do
    case $arg in
        --release|-r) BUILD_TYPE="release" ;;
        --install) INSTALL=true ;;
        --no-run) RUN=false ;;
        --arch) ARCH="universal" ;;
        --help|-h)
            echo "Usage: $0 [--release|-r] [--install] [--no-run] [--arch]"
            echo "  Default: debug build, no install, auto-run, native arch"
            echo "  --release, -r: release build"
            echo "  --install: copy to /Applications"
            echo "  --no-run: do not kill/launch the app"
            echo "  --arch: build universal binary (arm64 + x86_64)"
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

# Universal build via swift build (supports both archs in one command since Swift 5.9)
echo "🏗️  Building universal binary (arm64 + x86_64)..."
swift build -c release --arch arm64 --arch x86_64
cp ".build/apple/Products/Release/$APP_NAME" "$BUILD_DIR/$APP_NAME"
echo "✅ Universal binary copied to $BUILD_DIR"

APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"

echo "📦 Creating .app bundle..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"

cp "$BUILD_DIR/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/"

# Copy icon
if [ -f "$PROJECT_DIR/AppIcon.icns" ]; then
    cp "$PROJECT_DIR/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/"
elif [ -f "$PROJECT_DIR/Sources/NetMonitor/AppIcon.icns" ]; then
    cp "$PROJECT_DIR/Sources/NetMonitor/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/"
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
    pkill -f "$APP_NAME.app" 2>/dev/null || true
    sleep 0.5
    echo "🚀 Launching..."
    open "$PROJECT_DIR/$APP_NAME.app"
fi