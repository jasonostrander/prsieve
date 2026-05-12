#!/bin/bash
set -euo pipefail

# End-to-end test of Sparkle auto-update.
#
# Builds two signed + notarized zips (OLD_VERSION + NEW_VERSION), installs
# OLD to /Applications, serves NEW over localhost, points the installed app at
# the local feed, then waits for you to click "Check for Updates..." and watch
# Sparkle do its thing.
#
# Usage:
#   ./scripts/test_sparkle.sh                     # uses 0.9.0 -> 0.9.1
#   OLD_VERSION=0.5.0 NEW_VERSION=0.6.0 ./scripts/test_sparkle.sh
#   PORT=9000 ./scripts/test_sparkle.sh
#
# Prerequisites (see RELEASING.md):
#   - Sparkle private key in Keychain (generate_keys has been run)
#   - resources/Info.plist has a real SUPublicEDKey (not the placeholder)
#   - Notarization keychain profile is set up
#
# Each release.sh invocation notarizes, so this script takes ~3-4 minutes total.

cd "$(dirname "$0")/.."

OLD_VERSION="${OLD_VERSION:-0.9.0}"
NEW_VERSION="${NEW_VERSION:-0.9.1}"
PORT="${PORT:-8765}"
TEST_DIR=".build/sparkle_test"
BUNDLE_ID="com.jasonostrander.prsieve"
APPCAST_HAD_BACKUP=0
SERVER_PID=""

# --- Preflight ---------------------------------------------------------------

if grep -q "REPLACE_WITH_GENERATED_PUBLIC_ED_KEY" resources/Info.plist; then
    echo "error: resources/Info.plist still has the placeholder SUPublicEDKey."
    echo "       Run .build/artifacts/sparkle/Sparkle/bin/generate_keys and paste the key in."
    exit 1
fi

if lsof -nP -iTCP:"$PORT" -sTCP:LISTEN >/dev/null 2>&1; then
    echo "error: port $PORT already in use. Set PORT=... or free it."
    exit 1
fi

if [[ -d /Applications/PRSieve.app ]]; then
    echo "warning: /Applications/PRSieve.app already exists and will be replaced."
    echo "         If you have a real install you care about, back it up now."
    read -r -p "Continue? [y/N] " ans
    [[ "$ans" =~ ^[Yy]$ ]] || exit 1
fi

# --- Cleanup -----------------------------------------------------------------

cleanup() {
    local rc=$?
    echo ""
    echo "==> Cleaning up..."
    if [[ -n "$SERVER_PID" ]]; then
        kill "$SERVER_PID" 2>/dev/null || true
    fi
    defaults delete "$BUNDLE_ID" SUFeedURL 2>/dev/null || true
    defaults delete "$BUNDLE_ID" SULastCheckTime 2>/dev/null || true
    defaults delete "$BUNDLE_ID" SUSkippedVersion 2>/dev/null || true
    if [[ "$APPCAST_HAD_BACKUP" -eq 1 ]]; then
        mv "$TEST_DIR/appcast.xml.bak" appcast.xml
        echo "    Restored original appcast.xml."
    else
        rm -f appcast.xml
        echo "    Removed test-generated appcast.xml."
    fi
    echo "    Test DMGs preserved in $TEST_DIR/ for inspection."
    echo "    /Applications/PRSieve.app left in place — delete manually if unwanted."
    exit $rc
}
trap cleanup EXIT INT TERM

rm -rf "$TEST_DIR"
mkdir -p "$TEST_DIR"

if [[ -f appcast.xml ]]; then
    cp appcast.xml "$TEST_DIR/appcast.xml.bak"
    APPCAST_HAD_BACKUP=1
fi

# --- Build OLD ---------------------------------------------------------------

echo "==> Building $OLD_VERSION (will notarize, ~90s)..."
./release.sh "$OLD_VERSION" --no-publish
cp -R "dist/PRSieve.app" "$TEST_DIR/PRSieve-$OLD_VERSION.app"
cp dist/PRSieve.zip "$TEST_DIR/PRSieve-$OLD_VERSION.zip"

# --- Build NEW ---------------------------------------------------------------

echo ""
echo "==> Building $NEW_VERSION (will notarize, ~90s)..."
./release.sh "$NEW_VERSION" --no-publish
cp dist/PRSieve.zip "$TEST_DIR/PRSieve-$NEW_VERSION.zip"

# release.sh just regenerated appcast.xml with the GitHub Release URL.
# Rewrite the enclosure URL to point at our local server, and copy into TEST_DIR
# so the http.server serves it alongside the zip.
sed -i '' "s|url=\"https://github.com/[^\"]*\"|url=\"http://localhost:$PORT/PRSieve-$NEW_VERSION.zip\"|" appcast.xml
cp appcast.xml "$TEST_DIR/appcast.xml"

# Sanity-check the signature parses
SIGN_UPDATE=$(find .build/artifacts -name "sign_update" -type f -not -path '*old_dsa_scripts*' | head -1)
echo "==> Verifying EdDSA signature on the $NEW_VERSION zip..."
"$SIGN_UPDATE" --verify "$TEST_DIR/PRSieve-$NEW_VERSION.zip" || {
    echo "error: EdDSA signature verification failed."
    exit 1
}

# --- Install OLD -------------------------------------------------------------

echo ""
echo "==> Installing $OLD_VERSION to /Applications..."
pkill -9 PRSieve 2>/dev/null || true
sleep 1
rm -rf /Applications/PRSieve.app
cp -R "$TEST_DIR/PRSieve-$OLD_VERSION.app" /Applications/PRSieve.app
INSTALLED=$(defaults read /Applications/PRSieve.app/Contents/Info CFBundleShortVersionString)
echo "    Installed: $INSTALLED"

# --- Override the feed URL via UserDefaults ----------------------------------

echo "==> Pointing installed app at http://localhost:$PORT/appcast.xml"
defaults write "$BUNDLE_ID" SUFeedURL "http://localhost:$PORT/appcast.xml"
defaults write "$BUNDLE_ID" SUEnableAutomaticChecks -bool true
defaults delete "$BUNDLE_ID" SULastCheckTime 2>/dev/null || true
defaults delete "$BUNDLE_ID" SUSkippedVersion 2>/dev/null || true

# --- Serve --------------------------------------------------------------------

echo "==> Serving $TEST_DIR/ on port $PORT..."
( cd "$TEST_DIR" && python3 -m http.server "$PORT" >/dev/null 2>&1 ) &
SERVER_PID=$!
sleep 1

# Confirm the server is reachable
if ! curl -sf "http://localhost:$PORT/appcast.xml" >/dev/null; then
    echo "error: local HTTP server didn't come up on port $PORT."
    exit 1
fi

# --- Launch & wait ------------------------------------------------------------

echo "==> Launching /Applications/PRSieve.app"
open /Applications/PRSieve.app
sleep 2

cat <<EOF

================================================================
  Sparkle test ready. Installed: $OLD_VERSION  Feed advertises: $NEW_VERSION
================================================================

Now manually:
  1. Right-click the PRSieve menu bar icon
  2. Click "Check for Updates..."
  3. Expected: a "Version $NEW_VERSION is now available" dialog
  4. Click Install — Sparkle should download, relaunch, and bump the app

To watch Sparkle's debug log in a second terminal:
  log stream --predicate 'subsystem == "org.sparkle-project.Sparkle"' --level debug

After the update completes, verify the bump:
  defaults read /Applications/PRSieve.app/Contents/Info CFBundleShortVersionString
  (should print: $NEW_VERSION)

Press Enter when done to clean up...
EOF
read -r
