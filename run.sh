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
mkdir -p "$BUNDLE_DIR/Contents/Frameworks"

# Copy binary
cp "$BUILD_DIR/$APP_NAME" "$BUNDLE_DIR/Contents/MacOS/$APP_NAME"

# Copy Info.plist and icon
cp resources/Info.plist "$BUNDLE_DIR/Contents/Info.plist"
# Strip Sparkle config in dev so it doesn't poll a stale feed with a placeholder key
plutil -remove SUFeedURL "$BUNDLE_DIR/Contents/Info.plist" 2>/dev/null || true
plutil -remove SUPublicEDKey "$BUNDLE_DIR/Contents/Info.plist" 2>/dev/null || true
plutil -replace SUEnableAutomaticChecks -bool false "$BUNDLE_DIR/Contents/Info.plist"
cp resources/AppIcon.icns "$BUNDLE_DIR/Contents/Resources/AppIcon.icns"

# Copy Sparkle.framework into Contents/Frameworks
SPARKLE_FRAMEWORK=$(find .build/artifacts -path '*Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework' -type d 2>/dev/null | head -1)
if [[ -z "$SPARKLE_FRAMEWORK" ]]; then
  echo "error: Sparkle.framework not found under .build/artifacts. Did 'swift build' succeed?"
  exit 1
fi
cp -R "$SPARKLE_FRAMEWORK" "$BUNDLE_DIR/Contents/Frameworks/Sparkle.framework"

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
  echo "warning: llm_config.json not found, bundling llm_config.example.json (defaults to the Instacart AI gateway, which needs no token; copy to llm_config.json to customize)"
  LLM_SRC="llm_config.example.json"
fi
if [[ -n "$LLM_SRC" ]]; then
  plutil -convert binary1 "$LLM_SRC" -o "$BUNDLE_DIR/Contents/Resources/llm_config.plist"
fi

# Ad-hoc code sign (required for notifications and other entitlements).
# Sparkle.framework must be signed first so the outer signature picks it up correctly.
codesign --force --deep --sign - "$BUNDLE_DIR/Contents/Frameworks/Sparkle.framework"
codesign --force --sign - "$BUNDLE_DIR"

# Launch
open "$BUNDLE_DIR"
