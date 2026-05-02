#!/bin/bash
set -euo pipefail

APP_NAME="PRSieve"
BUILD_DIR=".build/release"
DIST_DIR="dist"
BUNDLE_DIR="$DIST_DIR/${APP_NAME}.app"
DMG_PATH="$DIST_DIR/${APP_NAME}.dmg"

# Generate build info (git hash + build date), reset on exit
./scripts/generate_build_info.sh
trap "git checkout -- Sources/PRSieve/BuildInfo.swift 2>/dev/null || true" EXIT

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

# Copy LLM config (gitignored; falls back to main worktree, then example template)
MAIN_WORKTREE="$(git worktree list --porcelain | grep '^worktree' | head -1 | awk '{print $2}')"
if [[ -f llm_config.json ]]; then
  cp llm_config.json "$BUNDLE_DIR/Contents/Resources/llm_config.json"
elif [[ -f "${MAIN_WORKTREE}/llm_config.json" ]]; then
  echo "note: using llm_config.json from main worktree (${MAIN_WORKTREE})"
  cp "${MAIN_WORKTREE}/llm_config.json" "$BUNDLE_DIR/Contents/Resources/llm_config.json"
elif [[ -f llm_config.example.json ]]; then
  echo "warning: llm_config.json not found, bundling llm_config.example.json (LLM will be disabled until apiKey is set)"
  cp llm_config.example.json "$BUNDLE_DIR/Contents/Resources/llm_config.json"
fi

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
