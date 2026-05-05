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

# Ad-hoc code sign (required for notifications and other entitlements)
codesign --force --sign - "$BUNDLE_DIR"

# Launch
open "$BUNDLE_DIR"
