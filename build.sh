#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

APP="PPTRemote.app"
BUNDLE_ID="local.pptremote"

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
    <key>CFBundleVersion</key><string>1.0</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleExecutable</key><string>PPTRemote</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
    <key>NSMicrophoneUsageDescription</key><string>Not used.</string>
</dict>
</plist>
PLIST

swiftc \
    -O \
    -parse-as-library \
    -target arm64-apple-macos13.0 \
    -framework AppKit \
    -framework AVFoundation \
    -framework MediaPlayer \
    -o "$APP/Contents/MacOS/PPTRemote" \
    App.swift

# Ad-hoc sign: required for a stable Accessibility permission entry, otherwise
# macOS re-prompts on every rebuild.
codesign --force --deep --sign - "$APP"

echo "Built $APP"

# Install to /Applications, so the copy you launch is never stale.
# Pass --no-install to build in place only.
if [[ "${1:-}" != "--no-install" ]]; then
    pkill -f "/Applications/$APP" 2>/dev/null || true
    rm -rf "/Applications/${APP:?}"
    cp -R "$APP" /Applications/
    echo "Installed to /Applications/$APP"
    echo "NOTE: re-approve Accessibility if the signature changed."
fi
