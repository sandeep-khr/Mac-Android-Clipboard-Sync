#!/bin/bash
# One-time setup to enable *automatic* Android→Mac clipboard capture (Milestone
# B3). Without this, phone→Mac still works via the "Send clipboard" Quick
# Settings tile and the share sheet — this just makes it automatic.
#
# It grants two permissions over adb that a normal app can't grant itself:
#   READ_LOGS          — so the app can watch logcat for the clipboard-change line
#   SYSTEM_ALERT_WINDOW — so it can raise the invisible read-window from background
# The grants persist across reboots. Nothing here needs root.
#
# Prereq: the phone is attached over adb (USB or `adb connect <ip:port>` after
# wireless-debugging pairing). Usage:  ./setup-android-auto.sh
set -euo pipefail

PKG="com.clipsync.android"
ADB="${ADB:-adb}"

if ! "$ADB" get-state >/dev/null 2>&1; then
    echo "✗ No device on adb. Pair/connect the phone first (wireless debugging), then re-run." >&2
    exit 1
fi

echo "▶ Granting READ_LOGS…"
"$ADB" shell pm grant "$PKG" android.permission.READ_LOGS

echo "▶ Allowing SYSTEM_ALERT_WINDOW…"
"$ADB" shell appops set "$PKG" SYSTEM_ALERT_WINDOW allow

echo "▶ Restarting the app so the grants take effect…"
"$ADB" shell am force-stop "$PKG"
"$ADB" shell am start -n "$PKG/.MainActivity" >/dev/null

echo ""
echo "✓ Automatic capture enabled. Copy anything on the phone → it lands on the Mac."
echo "  (If it doesn't, the tile / share sheet still work as the manual fallback.)"
