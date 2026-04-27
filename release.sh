#!/bin/bash
set -euo pipefail

APP_NAME="PRSieve"
BUILD_DIR=".build/release"
DIST_DIR="dist"
BUNDLE_DIR="$DIST_DIR/${APP_NAME}.app"
DMG_PATH="$DIST_DIR/${APP_NAME}.dmg"

# Build in release mode
swift build -c release

# Reset dist directory
rm -rf "$DIST_DIR"
mkdir -p "$BUNDLE_DIR/Contents/MacOS"
mkdir -p "$BUNDLE_DIR/Contents/Resources"

# Copy binary
cp "$BUILD_DIR/$APP_NAME" "$BUNDLE_DIR/Contents/MacOS/$APP_NAME"

# Copy Info.plist and icon
cp resources/Info.plist "$BUNDLE_DIR/Contents/Info.plist"
cp resources/AppIcon.icns "$BUNDLE_DIR/Contents/Resources/AppIcon.icns"

# Ad-hoc code sign
codesign --force --deep --sign - "$BUNDLE_DIR"

# Build DMG
hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$BUNDLE_DIR" \
    -ov \
    -format UDZO \
    "$DMG_PATH"

# Open the folder containing the DMG
open "$DIST_DIR"

echo ""
echo "Release built: $DMG_PATH"
