#!/bin/bash
set -euo pipefail

APP_NAME="PRSieve"
BUILD_DIR=".build/debug"
BUNDLE_DIR=".build/${APP_NAME}.app"

# Generate build info (git hash + build date), reset on exit
./scripts/generate_build_info.sh
trap "git checkout -- Sources/PRSieve/BuildInfo.swift 2>/dev/null || true" EXIT

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

# Copy LLM config (gitignored; falls back to example template)
if [[ -f llm_config.json ]]; then
  cp llm_config.json "$BUNDLE_DIR/Contents/Resources/llm_config.json"
elif [[ -f llm_config.example.json ]]; then
  echo "warning: llm_config.json not found, bundling llm_config.example.json (LLM will be disabled until apiKey is set)"
  cp llm_config.example.json "$BUNDLE_DIR/Contents/Resources/llm_config.json"
fi

# Ad-hoc code sign (required for notifications and other entitlements)
codesign --force --sign - "$BUNDLE_DIR"

# Launch
open "$BUNDLE_DIR"
