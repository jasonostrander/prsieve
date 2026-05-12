# Releasing PRSieve

PRSieve uses [Sparkle](https://sparkle-project.org/) to push auto-updates to
installed copies. This is a one-time setup, then a single command per release.

## One-time setup

### 1. Generate the Sparkle EdDSA signing key

```bash
swift build   # ensures the Sparkle tools are downloaded into .build/artifacts
.build/artifacts/sparkle/Sparkle/bin/generate_keys
```

This stores the **private key** in your macOS Keychain (as a generic password
named `https://sparkle-project.org`) and prints a **public key**.

Keep the private key safe. If you lose it, you can no longer ship updates that
existing installs will accept — you'd have to re-issue the app with a new key
and force users to reinstall.

To export a backup:

```bash
.build/artifacts/sparkle/Sparkle/bin/generate_keys -x sparkle_private_key.txt
# Store this file somewhere safe (1Password, encrypted backup). Do NOT commit it.
```

### 2. Embed the public key in `resources/Info.plist`

Replace the `REPLACE_WITH_GENERATED_PUBLIC_ED_KEY` placeholder with the public
key from the previous step:

```xml
<key>SUPublicEDKey</key>
<string>YOUR_PUBLIC_KEY_HERE</string>
```

Commit this change. It must ship in every released build.

### 3. Verify the appcast URL points at this repo

`SUFeedURL` in `resources/Info.plist` is currently:
`https://raw.githubusercontent.com/jasonostrander/prsieve/main/appcast.xml`

If your fork lives elsewhere, edit it accordingly. The repo must be public for
this URL to serve unauthenticated.

### 4. (One-time) commit an empty `appcast.xml`

`release.sh` regenerates `appcast.xml` on every release, but the *first*
release needs the file to exist or Sparkle won't have anything to read on
already-installed builds. The first time you run `./release.sh`, it'll create
and commit it for you.

## Cutting a release

```bash
./release.sh 1.0.1                # version arg is required, semver only
./release.sh 1.0.1 --no-publish   # build + sign locally without tagging or pushing
```

What it does, in order:

1. Bumps `CFBundleShortVersionString` and `CFBundleVersion` in the bundled
   `Info.plist` (the source file stays at `0.0.0`).
2. Builds in release mode, copies `Sparkle.framework` into the bundle, and
   Developer ID-signs everything with hardened runtime + secure timestamp.
3. Zips the signed `.app` (via `ditto -c -k --sequesterRsrc --keepParent`).
4. Notarizes the zip via the `PRSieve-notarize` keychain profile, staples the
   ticket onto the `.app`, then re-zips so the archive contains the stapled
   bundle.
5. EdDSA-signs the zip using the Keychain-stored private key.
6. Regenerates `appcast.xml` with the new version, signature, length, and
   download URL.
7. Unless `--no-publish` is passed: commits `appcast.xml`, tags `vX.Y.Z`,
   pushes both to `origin`, and creates a GitHub Release with the zip
   attached.

Existing installs poll the appcast (default once per day, or whenever the user
opens the popover and Sparkle's timer fires) and will prompt to install the new
version. The download URL is computed deterministically from the tag, so the
GitHub Release upload must succeed for users to actually receive the update.

### Why zip, not DMG?

Apple's notary service consistently rejects DMG-packaged bundles that contain
`Sparkle.framework` with `the signature of the binary is invalid` on the main
app binary + Sparkle dylib — even when the bytes inside the DMG are byte-for-
byte identical to a notarization-Accepted zip of the same `.app` (verified by
mounting the DMG and `shasum`-ing). Reproduced with both APFS and HFS+ inner
filesystems, both UDZO and UDRO formats, and multiple variations of the
signing pipeline (`--deep`, manual bottom-up, with/without `--remove-signature`
first, with/without `--preserve-metadata`). The zip path Just Works, and
Sparkle 2.x handles `.zip` updates natively, so we ship the zip.

## Testing the update flow locally

Before pushing your first real release, verify Sparkle works end-to-end without
touching GitHub:

```bash
./scripts/test_sparkle.sh
```

This builds two notarized zips (default 0.9.0 → 0.9.1), installs the older one
to `/Applications`, serves the newer one on `http://localhost:8765`, and points
the installed app at the local feed via `defaults write SUFeedURL`. You then
manually right-click the menu bar icon → **Check for Updates…** and watch
Sparkle download, verify the EdDSA signature, and relaunch into the newer
build.

Each `release.sh` call notarizes, so the script takes ~3-4 minutes. Override
versions or port with env vars:

```bash
OLD_VERSION=0.5.0 NEW_VERSION=0.6.0 PORT=9000 ./scripts/test_sparkle.sh
```

The script restores your `appcast.xml`, kills the HTTP server, and unsets the
local `SUFeedURL` UserDefault on exit. Test zips are left in
`.build/sparkle_test/` for inspection, and `/Applications/PRSieve.app` is left
at the post-update version — delete it manually if you don't want it.

## Troubleshooting

**`sign_update` says "no key found"** — you haven't run `generate_keys` yet, or
your Keychain access prompt was denied. Re-run `generate_keys`.

**Sparkle says "the update is improperly signed"** — the public key in
`Info.plist` of the *installed* build doesn't match the private key that
signed the new DMG. Either you regenerated keys, or the wrong copy is
installed. Either way: ship a new release with the matching public key and
have users reinstall manually.

**Notarization stalls** — `xcrun notarytool log <submission-id>
--keychain-profile PRSieve-notarize` shows the failure log.
