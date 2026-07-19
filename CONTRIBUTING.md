# Contributing to ClipSync

Thanks for taking a look! This is a personal project, but issues and PRs are
welcome.

## Ways to help

- **Report a bug** — open an issue (there's a template). ColorOS/OEM-specific
  behaviour is especially useful since Android background rules vary a lot.
- **Suggest a feature** — check the [open issues](../../issues) first; a few
  bigger ones (SAS pairing, image support) are already tracked.
- **Send a PR** — small, focused changes are easiest to review.

## Project layout

- `mac/ClipSyncCore` — Swift package: menu-bar app + core sync (watcher, crypto,
  WebSocket server) + a `clipsync-cli` for local testing.
- `android/ClipSyncAndroid` — the Kotlin/Android app.
- `docs/` — protocol spec, pairing flow, and roadmap notes.

## Building & testing

```bash
# Mac
cd mac/ClipSyncCore && swift test          # unit tests
swift run clipsync-menubar                 # run the menu-bar app

# Android
cd android/ClipSyncAndroid && ./gradlew assembleDebug
./gradlew testDebugUnitTest                # crypto contract tests
```

CI runs the Swift tests and the Android build on every push and PR, so please
make sure both pass locally before opening a PR.

## Crypto note

The Mac (CryptoKit) and Android (BouncyCastle) crypto must stay byte-compatible.
Both sides have known-answer-vector tests pinning the SAS code and session-key
derivation — if you touch anything in the crypto path, keep those green on both
platforms.
