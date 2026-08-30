#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

APP="PPTRemote.app"
BUNDLE_ID="local.pptremote"
DEPLOYMENT_TARGET="13.0"

# Version stamped into the bundle. The release workflow and the Homebrew
# formula both set this; a plain local build gets a dev marker.
VERSION="${PPTREMOTE_VERSION:-0.0.0-dev}"

# Architectures to compile. Defaults to the machine doing the building, which
# is what a Homebrew source install wants. Set to "arm64 x86_64" for a
# universal bundle.
ARCHS="${PPTREMOTE_ARCHS:-$(uname -m)}"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>PPTRemote</string>
    <key>CFBundleDisplayName</key><string>PowerPoint Headphone Remote</string>
    <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
    <key>CFBundleVersion</key><string>${VERSION}</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundleExecutable</key><string>PPTRemote</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>LSMinimumSystemVersion</key><string>${DEPLOYMENT_TARGET}</string>
    <key>LSUIElement</key><true/>
    <key>NSMicrophoneUsageDescription</key><string>Not used.</string>
</dict>
</plist>
PLIST

BIN="$APP/Contents/MacOS/PPTRemote"
SLICES=()
TMPDIR_BUILD="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_BUILD"' EXIT

for arch in $ARCHS; do
    out="$TMPDIR_BUILD/PPTRemote-$arch"
    swiftc \
        -O \
        -parse-as-library \
        -target "${arch}-apple-macos${DEPLOYMENT_TARGET}" \
        -framework AppKit \
        -framework AVFoundation \
        -framework MediaPlayer \
        -o "$out" \
        App.swift
    SLICES+=("$out")
done

if [[ ${#SLICES[@]} -gt 1 ]]; then
    lipo -create -output "$BIN" "${SLICES[@]}"
else
    cp "${SLICES[0]}" "$BIN"
fi

# Ad-hoc sign: required for a stable Accessibility permission entry, otherwise
# macOS re-prompts on every rebuild.
codesign --force --deep --sign - "$APP"

echo "Built $APP ($VERSION, $ARCHS)"

# Install to /Applications, so the copy you launch is never stale.
# Pass --no-install to build in place only.
if [[ "${1:-}" != "--no-install" ]]; then
    pkill -f "/Applications/$APP" 2>/dev/null || true
    rm -rf "/Applications/${APP:?}"
    cp -R "$APP" /Applications/
    echo "Installed to /Applications/$APP"
    echo "NOTE: re-approve Accessibility if the signature changed."
fi
