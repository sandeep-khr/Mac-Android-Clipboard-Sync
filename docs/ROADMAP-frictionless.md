# Roadmap: reaching Apple-Universal-Clipboard-level frictionless UX

Distilled from a deep-research pass (2026-07, 24 sources, adversarially verified).
Confidence tags: **[confirmed]** = 3/3 verifier votes; **[strong]** = reputable
source, not independently re-verified; **[plausible]** = single source / forum.

## The one hard constraint

**Android 10+ forbids background apps from reading the clipboard.** [confirmed]
(`developer.android.com/privacy-and-security/risks/secure-clipboard-handling`;
KDE Connect docs). This is the *only* thing standing between us and fully
automatic Android→Mac sync. Mac→Android has no such limit — which is why that
direction already works end to end.

**The ceiling check confirms this is a platform wall, not our shortcoming:**
- Google's own Pixel clipboard sync uses the privileged system permission
  `READ_CLIPBOARD_IN_BACKGROUND`, not available to third-party apps. [strong]
- An OS-level "Universal Clipboard" is rumored for Android 17 via the Companion
  Device / Continuity framework — future, not usable today. [strong]
- Microsoft Phone Link's clipboard sync is gated to OEM-partnered devices, and as
  of a Sept 2025 preview was still **Windows→Android only** — even Microsoft
  hadn't solved background Android reads without OEM privileges. [strong]

So there is no third-party API for automatic background clipboard read. The
question is which *workaround* to use.

## Android→Mac: the viable routes (how real apps do it)

Ordered by friction. KDE Connect ships #1–#3. [confirmed]

1. **Manual push button** — a "Send Clipboard" action in the persistent
   foreground-service notification. Always works, one tap per push. [confirmed]
2. **Quick Settings tile** — a "Send clipboard" tile in the pull-down shade
   (Android 14+). One tap, always works, no special permission. [confirmed]
3. **Automatic via one-time adb grant (the KDE Connect trick)** [confirmed]:
   ```
   adb shell pm grant <pkg> android.permission.READ_LOGS
   adb shell appops set <pkg> SYSTEM_ALERT_WINDOW allow
   adb shell am force-stop <pkg>
   ```
   The app watches **its own logcat** for the "denied clipboard access" line the
   system prints on a copy, then briefly raises an **invisible focused window** to
   legally read the clipboard and closes it. Fully automatic; survives reboot
   (grants persist). Note: it is **not** an `appops READ_CLIPBOARD allow` grant —
   that op isn't grantable per-app; READ_LOGS + SYSTEM_ALERT_WINDOW is the real
   recipe.
4. **Default IME** — a keyboard app can always read the clipboard, but switching
   the user's daily keyboard is heavy. Not pursuing.
5. **Share-sheet target** — highest friction, always works. Cheap fallback.

**Why this is a great fit for us:** we already use **wireless adb** to deploy, so
the "one-time adb setup" is friction the user has effectively already paid — the
Mac app can run the grants during pairing. On Android 15/ColorOS we'll try the
adb route and fall back to tile+share if a denial is unrecoverable.

## ColorOS / Oppo survival (Oppo rated 4/5 killer on dontkillmyapp) [plausible]

A foreground service is necessary but **not sufficient** on ColorOS. To survive
long-term the user must: enable **Allow Auto Start-up** (App info), **disable
battery optimization**, and **lock the app in recents**. Screen-off can still kill
background/accessibility services. Mitigations we ship:
- `BOOT_COMPLETED` receiver → restart the service after reboot.
- In-app **setup checklist** that deep-links these ColorOS toggles and explains
  them, so setup is guided rather than folklore.

## Fast auto-reconnect over LAN

- NSD discovery is **battery-expensive; stop it when connected**, re-issue
  `discoverServices()` only while reconnecting. [confirmed]
- Reconnect with **exponential backoff**: 1s base, ×2, cap 30s, ±50% jitter. [strong]
- Some devices filter multicast — hold a **`WifiManager.MulticastLock`** during
  discovery. [plausible] (cheap; we'll add it)
- Cache the last resolved `host:port` and try it **first** (skip discovery) for a
  near-instant reconnect; fall back to NSD if the direct dial fails.
- Mac side: a sleeping Mac is woken by a TCP SYN to its **Bonjour-advertised**
  port (Sleep Proxy) — so keep the listener advertised (we do). [strong] Avoid
  cancel/restart churn on `NWListener` (can hit EADDRINUSE on-device). [plausible]

## Mac-side native polish (no paid Apple Developer account needed)

- A SwiftPM binary must be wrapped in a **`.app` bundle** to behave as a real
  menu-bar app (focusable windows, menu bar). Assemble by hand: `Info.plist`
  (+`LSUIElement` for menu-bar-only) + `Contents/MacOS/<bin>` + **ad-hoc
  codesign** (`codesign --sign -`). [strong]
- **Launch at Login** via `SMAppService.mainApp.register()` — requires a bundle. [strong]
- Locally built + ad-hoc signed apps get **no quarantine attribute**, so they run
  without Gatekeeper/notarization. Notarization needs a paid account and is
  **unnecessary for personal use**. (macOS 15.1 did remove the old right-click
  Gatekeeper bypass, so build-it-yourself is the clean path.) [strong]

## Build plan

**Milestone A — Reliability & polish (always-on Mac→Android):**
- A1 Android auto-reconnect (cached dial → NSD fallback, backoff+jitter, multicast lock).
- A2 ColorOS survival: `BOOT_COMPLETED` receiver + guided setup checklist.
- A3 Mac `.app` bundle + ad-hoc sign + Launch-at-Login (`SMAppService`).

**Milestone B — Android→Mac (the "vice versa"):**
- B1 Mac applies inbound clipboard updates to `NSPasteboard` (+ echo-suppression
  via `origin`+hash so A→B→A can't loop).
- B2 Android Quick Settings tile + share-sheet target (no-permission push).
- B3 Automatic capture via the READ_LOGS invisible-window trick, adb grants run
  from the Mac during pairing; tile/share remain the fallback.

**Milestone C — later:** QR pairing, rich types (images), multi-device.
