# ClipSyncAndroid — receiver spike

The smallest possible Android app that answers one question:

> Copy text on the Mac → does it land on the Oppo K14?

It does exactly three things: find the Mac (NSD), connect (WebSocket), and write
the received text to the Android clipboard (and show it on screen). **No pairing,
no encryption, no reconnect, no background service yet** — those come later. This
is a de-risking spike, not the finished app.

## Prerequisites

1. **Android Studio** installed on your MacBook (`developer.android.com/studio`).
2. Your **Oppo K14** with Developer Options + USB debugging on, connected by a
   **data** USB cable (see the main chat for the ColorOS steps).
3. The **Mac app running** on the same Wi-Fi network:
   ```bash
   cd mac/ClipSyncCore
   swift run clipsync-menubar
   ```
   (A clipboard icon appears in the Mac menu bar. Both devices must be on the
   **same Wi-Fi**, and Wi-Fi must be on — NSD does not work over cellular.)

## Run it

1. In Android Studio: **File → Open** → select `android/ClipSyncAndroid`.
2. Let Gradle sync. If it prompts to **upgrade the Android Gradle Plugin** or
   **download an SDK**, accept — that's normal.
3. Pick your Oppo K14 in the device dropdown, press **▶ Run**.
4. On the phone: tap **Connect to Mac**. Status should move through
   "Searching…" → "Found Mac…" → **"Connected ✅"**.
5. **Copy some text on your Mac.** Within ~1s the phone should show it under
   "Last received", and it should be on the phone's clipboard (long-press any
   text field → Paste to confirm).

## What we're actually testing

The screen shows the received text **separately** from the clipboard write on
purpose:

- Text appears under "Last received" but **won't paste** → the network path works;
  the problem is ColorOS restricting clipboard **writes** (the known risk). That's
  a useful, specific result.
- Nothing appears at all → discovery or connection failed (see below).
- Text appears **and** pastes → 🎉 the core idea works; we build up from here.

## If something doesn't work — tell me what you see

Likely first-run snags:

- **Gradle sync fails / "wrapper jar missing"** → in Android Studio run
  **File → Sync Project with Gradle Files**; it regenerates the wrapper. Paste me
  any red error text.
- **Stuck on "Searching for your Mac…"** → confirm the Mac app is running and
  both devices are on the same Wi-Fi; some routers block mDNS between devices
  ("AP/client isolation") — worth checking.
- **"Connection error…"** → usually the cleartext-`ws://` block; this app sets
  `usesCleartextTraffic="true"` to allow it, but note it if you see it.
- Anything else → screenshot the phone status line + paste any Logcat errors.

This app can't be compiled or tested from the assistant's environment, so expect
a round or two of fixes on the first real run.
