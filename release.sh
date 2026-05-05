#!/bin/bash
set -euo pipefail

APP_NAME="PRSieve"
BUILD_DIR=".build/release"
DIST_DIR="dist"
BUNDLE_DIR="$DIST_DIR/${APP_NAME}.app"
DMG_PATH="$DIST_DIR/${APP_NAME}.dmg"
SIGNING_IDENTITY="29E75AE1A9A90CE572CC83E91FC3457C634A7E85"
NOTARIZE_PROFILE="${NOTARIZE_PROFILE:-PRSieve-notarize}"

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
# Convert JSON → binary plist so corporate DLP doesn't strip it from the DMG.
MAIN_WORKTREE="$(git worktree list --porcelain | grep '^worktree' | head -1 | awk '{print $2}')"
LLM_SRC=""
if [[ -f llm_config.json ]]; then
  LLM_SRC="llm_config.json"
elif [[ -f "${MAIN_WORKTREE}/llm_config.json" ]]; then
  echo "note: using llm_config.json from main worktree (${MAIN_WORKTREE})"
  LLM_SRC="${MAIN_WORKTREE}/llm_config.json"
elif [[ -f llm_config.example.json ]]; then
  echo "warning: llm_config.json not found, bundling llm_config.example.json (LLM will be disabled until token is set)"
  LLM_SRC="llm_config.example.json"
fi
if [[ -n "$LLM_SRC" ]]; then
  plutil -convert binary1 "$LLM_SRC" -o "$BUNDLE_DIR/Contents/Resources/llm_config.plist"
fi

# Sign with Developer ID, hardened runtime, and secure timestamp (required for notarization)
# Sign inner binary first, then the bundle. Hardened runtime alone is enough — no sandbox.
codesign --force --options runtime --timestamp \
    --sign "$SIGNING_IDENTITY" \
    "$BUNDLE_DIR/Contents/MacOS/$APP_NAME"

codesign --force --options runtime --timestamp \
    --sign "$SIGNING_IDENTITY" \
    "$BUNDLE_DIR"

# Verify signature is valid for notarization
codesign --verify --verbose=2 "$BUNDLE_DIR"

# Build DMG
hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$BUNDLE_DIR" \
    -ov \
    -format UDZO \
    "$DMG_PATH"

# Notarize and staple
echo "Notarizing (this takes ~1 minute)..."
xcrun notarytool submit "$DMG_PATH" \
    --keychain-profile "$NOTARIZE_PROFILE" \
    --wait
xcrun stapler staple "$DMG_PATH"

# Open the folder containing the DMG
open "$DIST_DIR"

echo ""
echo "Release built and notarized: $DMG_PATH"
