#!/bin/bash
# Assembles a real ClipSync.app menu-bar bundle from the SwiftPM binary and
# ad-hoc signs it — no Xcode project, no paid Apple Developer account.
#
# Why a bundle: a bare SwiftPM binary can't take window focus / own the menu bar
# properly, and SMAppService "Launch at Login" needs a real app bundle. Ad-hoc
# signing + a locally built binary means no quarantine flag, so it runs without
# notarization for personal use.
#
# Usage:  ./build-app.sh   → produces mac/build/ClipSync.app
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
PKG="$HERE/ClipSyncCore"
APP_NAME="ClipSync"
APP="$HERE/build/$APP_NAME.app"

echo "▶ Building release binary…"
swift build -c release --product clipsync-menubar --package-path "$PKG"
BIN="$(swift build -c release --package-path "$PKG" --show-bin-path)/clipsync-menubar"

echo "▶ Assembling $APP …"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>ClipSync</string>
    <key>CFBundleDisplayName</key><string>ClipSync</string>
    <key>CFBundleIdentifier</key><string>com.clipsync.menubar</string>
    <key>CFBundleExecutable</key><string>ClipSync</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

echo "▶ Ad-hoc signing…"
codesign --force --deep --sign - "$APP"
codesign --verify --verbose "$APP"

echo ""
echo "✓ Built $APP"
echo "  Launch:  open \"$APP\"   (menu-bar icon, no Dock; toggle Launch at Login from its menu)"
