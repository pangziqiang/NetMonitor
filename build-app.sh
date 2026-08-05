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

# Embed Sparkle.framework (dynamic framework required by the auto-updater)
SPARKLE_FRAMEWORK=$(find "$PROJECT_DIR/.build/artifacts" -path "*macos-arm64_x86_64/Sparkle.framework" -maxdepth 6 2>/dev/null | head -1)
if [ -z "$SPARKLE_FRAMEWORK" ]; then
    SPARKLE_FRAMEWORK=$(find "$PROJECT_DIR/.build" -path "*apple/Products/Release/Sparkle.framework" -maxdepth 5 2>/dev/null | head -1)
fi
if [ -n "$SPARKLE_FRAMEWORK" ]; then
    mkdir -p "$APP_BUNDLE/Contents/Frameworks"
    cp -R "$SPARKLE_FRAMEWORK" "$APP_BUNDLE/Contents/Frameworks/"
    install_name_tool -add_rpath @executable_path/../Frameworks "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
    echo "📦 Embedded Sparkle.framework"
else
    echo "⚠️  Sparkle.framework not found, skipping embed"
fi

# Copy icon
if [ -f "$PROJECT_DIR/AppIcon.icns" ]; then
    cp "$PROJECT_DIR/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/"
elif [ -f "$PROJECT_DIR/Sources/NetMonitor/AppIcon.icns" ]; then
    cp "$PROJECT_DIR/Sources/NetMonitor/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/"
fi

cp "$PROJECT_DIR/Resources/Info.plist" "$APP_BUNDLE/Contents/Info.plist"

# Code-sign with a stable local identity (self-signed). Replace with Developer ID for public distribution.
CODESIGN_ID="NetMonitor Local Signing"
if security find-identity -v -p codesigning 2>/dev/null | grep -q "$CODESIGN_ID"; then
    codesign --force --deep --sign "$CODESIGN_ID" "$APP_BUNDLE"
    echo "✅ Code-signed with $CODESIGN_ID"
else
    echo "⚠️  codesign identity not found, app left unsigned"
fi

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
