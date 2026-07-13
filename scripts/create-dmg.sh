#!/bin/bash
# Create NetMonitor DMG for distribution
set -euo pipefail

APP_NAME="NetMonitor"
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/.build"

# find the .app bundle
if [ -d "$PROJECT_DIR/$APP_NAME.app" ]; then
    SRC_APP="$PROJECT_DIR/$APP_NAME.app"
elif [ -d "$BUILD_DIR/debug/$APP_NAME.app" ]; then
    SRC_APP="$BUILD_DIR/debug/$APP_NAME.app"
else
    echo "❌ $APP_NAME.app not found"
    exit 1
fi

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$PROJECT_DIR/Resources/Info.plist")
DMG_NAME="$APP_NAME-$VERSION.dmg"
DMG_DIR="$BUILD_DIR/dmg"
DMG_PATH="$PROJECT_DIR/$DMG_NAME"

echo "📦 Creating DMG: $DMG_PATH"
echo "   App: $SRC_APP"
echo "   Version: $VERSION"

rm -rf "$DMG_DIR" "$DMG_PATH"
mkdir -p "$DMG_DIR"
cp -R "$SRC_APP" "$DMG_DIR/"

# Create Applications folder symlink for drag-to-install
ln -s /Applications "$DMG_DIR/Applications"

# Strip quarantine if it was copied from a quarantined location
xattr -d com.apple.quarantine "$DMG_DIR/$APP_NAME.app" 2>/dev/null || true

# Create DMG
hdiutil create -volname "$APP_NAME" \
    -srcfolder "$DMG_DIR" \
    -ov -format UDZO \
    "$DMG_PATH" \
    -imagekey zlib-level=9

# Cleanup
rm -rf "$DMG_DIR"

echo "✅ DMG created: $DMG_PATH ($(du -sh "$DMG_PATH" | cut -f1))"
