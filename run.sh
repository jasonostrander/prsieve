#!/bin/bash
set -euo pipefail

APP_NAME="PRSieve"
BUILD_DIR=".build/debug"
BUNDLE_DIR=".build/${APP_NAME}.app"

# Build
swift build

# Create .app bundle
rm -rf "$BUNDLE_DIR"
mkdir -p "$BUNDLE_DIR/Contents/MacOS"
mkdir -p "$BUNDLE_DIR/Contents/Resources"

# Copy binary
cp "$BUILD_DIR/$APP_NAME" "$BUNDLE_DIR/Contents/MacOS/$APP_NAME"

# Copy Info.plist and icon
cp resources/Info.plist "$BUNDLE_DIR/Contents/Info.plist"
cp resources/AppIcon.icns "$BUNDLE_DIR/Contents/Resources/AppIcon.icns"

# Launch
open "$BUNDLE_DIR"
