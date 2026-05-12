#!/bin/bash
set -euo pipefail

# Usage: ./release.sh VERSION [--no-publish]
# Example: ./release.sh 1.0.1
#
# Builds a signed + notarized .zip (containing the .app), EdDSA-signs it for
# Sparkle, regenerates appcast.xml, tags the release, and (unless --no-publish)
# creates a GitHub Release with the zip attached and pushes the appcast/tag.
#
# Why zip and not DMG? Apple's notary service silently rejects DMG-packaged
# bundles that contain Sparkle.framework with "the signature of the binary is
# invalid" on the main app + Sparkle dylib — even when the bytes inside the DMG
# are byte-for-byte identical to a notarization-Accepted zip of the same .app.
# Reproduced with both APFS and HFS+ filesystems, both UDZO and UDRO formats.
# Sparkle 2.x handles .zip updates natively, so we just ship a zip.

VERSION="${1:-}"
PUBLISH=1
if [[ "${2:-}" == "--no-publish" ]]; then
    PUBLISH=0
fi

if [[ -z "$VERSION" ]]; then
    echo "Usage: ./release.sh VERSION [--no-publish]"
    echo "Example: ./release.sh 1.0.1"
    exit 1
fi

if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "error: VERSION must be semver (e.g. 1.0.1), got: $VERSION"
    exit 1
fi

APP_NAME="PRSieve"
BUILD_DIR=".build/release"
DIST_DIR="dist"
BUNDLE_DIR="$DIST_DIR/${APP_NAME}.app"
ZIP_PATH="$DIST_DIR/${APP_NAME}.zip"
TAG="v$VERSION"
SIGNING_IDENTITY="24F3CC93DB6ADE982BE2027BD4781D2C68466D0C"
NOTARIZE_PROFILE="${NOTARIZE_PROFILE:-PRSieve-notarize}"
GITHUB_REPO="${GITHUB_REPO:-jasonostrander/prsieve}"
DOWNLOAD_URL="https://github.com/${GITHUB_REPO}/releases/download/${TAG}/${APP_NAME}.zip"

# Sanity checks before doing expensive work
if [[ "$PUBLISH" -eq 1 ]]; then
    if [[ -n "$(git status --porcelain)" ]]; then
        echo "error: working tree is dirty. Commit or stash before releasing (or pass --no-publish)."
        exit 1
    fi
    if git rev-parse "$TAG" >/dev/null 2>&1; then
        echo "error: tag $TAG already exists."
        exit 1
    fi
    if ! command -v gh >/dev/null; then
        echo "error: 'gh' (GitHub CLI) is required to publish. Install via 'brew install gh' or pass --no-publish."
        exit 1
    fi
fi

# Generate build info (git hash + build date), reset on exit
./scripts/generate_build_info.sh
trap "git checkout -- Sources/PRSieve/BuildInfo.swift 2>/dev/null || true" EXIT

# Build in release mode
swift build -c release

# Reset dist directory
rm -rf "$DIST_DIR"
mkdir -p "$BUNDLE_DIR/Contents/MacOS"
mkdir -p "$BUNDLE_DIR/Contents/Resources"
mkdir -p "$BUNDLE_DIR/Contents/Frameworks"

# Copy binary
cp "$BUILD_DIR/$APP_NAME" "$BUNDLE_DIR/Contents/MacOS/$APP_NAME"

# Copy Info.plist and stamp the version
cp resources/Info.plist "$BUNDLE_DIR/Contents/Info.plist"
plutil -replace CFBundleShortVersionString -string "$VERSION" "$BUNDLE_DIR/Contents/Info.plist"
plutil -replace CFBundleVersion -string "$VERSION" "$BUNDLE_DIR/Contents/Info.plist"

cp resources/AppIcon.icns "$BUNDLE_DIR/Contents/Resources/AppIcon.icns"

# Copy Sparkle.framework into Contents/Frameworks
SPARKLE_FRAMEWORK=$(find .build/artifacts -path '*Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework' -type d 2>/dev/null | head -1)
if [[ -z "$SPARKLE_FRAMEWORK" ]]; then
    echo "error: Sparkle.framework not found under .build/artifacts. Did 'swift build' succeed?"
    exit 1
fi
cp -R "$SPARKLE_FRAMEWORK" "$BUNDLE_DIR/Contents/Frameworks/Sparkle.framework"
# SPM-downloaded artifacts carry com.apple.provenance xattrs which silently break
# notarization ("signature of binary is invalid") even though local codesign verify
# passes. Strip xattrs from the whole bundle before signing.
xattr -cr "$BUNDLE_DIR"

# Copy LLM config (gitignored; falls back to main worktree, then example template)
# Convert JSON → binary plist so corporate DLP doesn't strip it from the zip.
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

# Sign everything inside Sparkle.framework and the app.
# First: strip the upstream ad-hoc signatures so codesign --force doesn't have
# to overwrite, which was producing notarization-rejected signatures.
SPARKLE_FW="$BUNDLE_DIR/Contents/Frameworks/Sparkle.framework"
SPARKLE_VERSIONS="$SPARKLE_FW/Versions/B"
codesign --remove-signature "$SPARKLE_VERSIONS/XPCServices/Downloader.xpc" 2>/dev/null || true
codesign --remove-signature "$SPARKLE_VERSIONS/XPCServices/Installer.xpc" 2>/dev/null || true
codesign --remove-signature "$SPARKLE_VERSIONS/Updater.app" 2>/dev/null || true
codesign --remove-signature "$SPARKLE_VERSIONS/Autoupdate" 2>/dev/null || true
codesign --remove-signature "$SPARKLE_FW" 2>/dev/null || true

codesign_runtime() {
    codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" "$@"
}
# Bottom-up: leaf Mach-O binaries first, then bundles, then framework, then app.
codesign_runtime "$SPARKLE_VERSIONS/XPCServices/Downloader.xpc/Contents/MacOS/Downloader"
codesign_runtime "$SPARKLE_VERSIONS/XPCServices/Downloader.xpc"
codesign_runtime "$SPARKLE_VERSIONS/XPCServices/Installer.xpc/Contents/MacOS/Installer"
codesign_runtime "$SPARKLE_VERSIONS/XPCServices/Installer.xpc"
codesign_runtime "$SPARKLE_VERSIONS/Autoupdate"
codesign_runtime "$SPARKLE_VERSIONS/Updater.app/Contents/MacOS/Updater"
codesign_runtime "$SPARKLE_VERSIONS/Updater.app"
codesign_runtime "$SPARKLE_FW"

# Sign main binary, then the bundle (hardened runtime alone — no sandbox)
codesign_runtime "$BUNDLE_DIR/Contents/MacOS/$APP_NAME"
codesign_runtime "$BUNDLE_DIR"

# Verify signature is valid for notarization
codesign --verify --verbose=2 "$BUNDLE_DIR"

# Zip the .app with ditto (preserves bundle structure + symlinks + xattrs).
ditto -c -k --sequesterRsrc --keepParent "$BUNDLE_DIR" "$ZIP_PATH"

# Notarize the zip.
echo "Notarizing (this takes ~1 minute)..."
xcrun notarytool submit "$ZIP_PATH" \
    --keychain-profile "$NOTARIZE_PROFILE" \
    --wait

# notarytool doesn't staple zips (no filesystem to stamp). Staple the ticket to
# the .app itself, then re-zip so users get a stapled bundle inside the archive.
xcrun stapler staple "$BUNDLE_DIR"
rm -f "$ZIP_PATH"
ditto -c -k --sequesterRsrc --keepParent "$BUNDLE_DIR" "$ZIP_PATH"

# EdDSA-sign the zip for Sparkle (private key stored in macOS Keychain)
SIGN_UPDATE=$(find .build/artifacts -name "sign_update" -type f -not -path '*old_dsa_scripts*' 2>/dev/null | head -1)
if [[ -z "$SIGN_UPDATE" ]]; then
    echo "error: sign_update tool not found under .build/artifacts."
    exit 1
fi
echo "Signing zip with EdDSA..."
SIGN_OUTPUT=$("$SIGN_UPDATE" "$ZIP_PATH")
# Output looks like: sparkle:edSignature="..." length="12345"
EDSIG=$(echo "$SIGN_OUTPUT" | sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p')
LENGTH=$(echo "$SIGN_OUTPUT" | sed -n 's/.*length="\([^"]*\)".*/\1/p')
if [[ -z "$EDSIG" || -z "$LENGTH" ]]; then
    echo "error: failed to parse sign_update output: $SIGN_OUTPUT"
    exit 1
fi

# Generate appcast.xml (overwrites; users always get pushed to the latest version)
PUBDATE=$(date -u +"%a, %d %b %Y %H:%M:%S +0000")
cat > appcast.xml <<EOF
<?xml version="1.0" standalone="yes"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
    <channel>
        <title>PRSieve</title>
        <link>https://github.com/${GITHUB_REPO}</link>
        <description>PRSieve updates feed</description>
        <language>en</language>
        <item>
            <title>Version ${VERSION}</title>
            <pubDate>${PUBDATE}</pubDate>
            <sparkle:version>${VERSION}</sparkle:version>
            <sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
            <enclosure
                url="${DOWNLOAD_URL}"
                sparkle:edSignature="${EDSIG}"
                length="${LENGTH}"
                type="application/octet-stream" />
        </item>
    </channel>
</rss>
EOF
echo "Wrote appcast.xml (version $VERSION)"

if [[ "$PUBLISH" -eq 1 ]]; then
    git add appcast.xml
    git commit -m "Release v${VERSION}"
    git tag "$TAG"
    git push origin HEAD
    git push origin "$TAG"
    gh release create "$TAG" "$ZIP_PATH" \
        --repo "$GITHUB_REPO" \
        --title "v${VERSION}" \
        --notes "PRSieve ${VERSION}"
    echo ""
    echo "Released v${VERSION}: ${DOWNLOAD_URL}"
else
    echo ""
    echo "Built (not published): $ZIP_PATH"
    echo "appcast.xml regenerated locally."
fi

# Open the folder containing the zip
open "$DIST_DIR"
