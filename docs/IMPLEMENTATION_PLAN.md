# ClipSync — Implementation Plan

This is the actionable, sequenced build plan. It builds on `BUILD_PLAN.md`
(the product/architecture spec on the `codex/build-plan` branch) and turns it
into concrete phases, files, and acceptance criteria.

Read `BUILD_PLAN.md` for the *why*. Read this for the *what to do next*.

---

## 0. Decisions (locked)

These were the open questions in `BUILD_PLAN.md` §16. Resolved against two goals:
**minimal user friction** and **eventual complete bidirectional, multi-format sync**.

| Decision | Choice | Rationale |
| --- | --- | --- |
| Mac app form | **Xcode menu bar app** wrapping a **`ClipSyncCore` Swift package** | A CLI can't launch at login, hold entitlements, or show pairing UI. Core stays a package so it's testable and reusable. |
| Mac WebSocket | **Network.framework** (`NWProtocolWebSocket`, `NWListener`, `NWBrowser`) | Native, zero deps, does WS framing + Bonjour in one stack, and is symmetric — a Mac can be server *and* client, which bidirectional sync needs. |
| Android WebSocket | **OkHttp** WebSocket + **NSD** | Standard, well-supported, reconnect-friendly. |
| Pairing UX | **Numeric SAS first, QR added later** | SAS needs no camera and is the simplest secure path; QR is a friction upgrade layered on the same key exchange. |
| Crypto | **X25519 + HKDF + AES-256-GCM**, long-term identity keys per device | Matches `BUILD_PLAN.md` §7. Identity keys are symmetric per device so bidirectional comes "for free". |
| Scope of v1 | **Mac → Android, `text/plain`, local Wi-Fi** | Unchanged from `BUILD_PLAN.md`. Everything below is designed to *extend* to bidirectional/multi-format without redesign. |

### Design principles that protect the future bidirectional goal
- **Symmetric protocol from day one.** Messages are not "Mac-only". Either peer
  can send `clipboard_update`; v1 simply only has the Mac emit them.
- **Both devices generate identity keypairs and store the peer's public key.**
  No "server key / client key" asymmetry that would block Android → Mac later.
- **`origin` field on every clipboard event** (device id) so an echo-suppression
  rule prevents A→B→A loops when both directions are live.
- **`mimeType` field present now** even though only `text/plain` is honored, so
  images/rich text slot in without a protocol bump.

---

## Current state (what already exists)

`mac/ClipSyncMac/` is a SwiftPM **executable** that works today:
- `PasteboardWatcher` — polls `NSPasteboard.general.changeCount` every 0.4s.
- `ClipboardNormalizer` — CRLF→LF, trims, SHA-256 hash.
- `ClipboardEvent` — model.
- `main.swift` — prints events on a run loop.

It already covers detection, normalization, and same-content duplicate
suppression. The next move is to make it a library, then put a real app and a
network transport around it.

---

## Target repository shape

```
Mac-Android-Clipboard-Sync/
├── README.md
├── BUILD_PLAN.md                 # product spec (codex branch)
├── docs/
│   ├── IMPLEMENTATION_PLAN.md    # this file
│   ├── protocol.md               # Phase 0 deliverable
│   ├── pairing-flow.md           # Phase 4 deliverable
│   └── glossary.md
├── mac/
│   ├── ClipSyncCore/             # Swift package: watcher, transport, crypto, models
│   │   ├── Package.swift
│   │   ├── Sources/ClipSyncCore/
│   │   └── Tests/ClipSyncCoreTests/
│   └── ClipSyncMac.xcodeproj/    # menu bar app shell, depends on ClipSyncCore
└── android/
    └── ClipSyncAndroid/          # Kotlin app (Android Studio / Gradle)
```

We do not build this all at once. It is the destination.

---

## Phase 0 — Spec & restructure (foundation) ✅ DONE

**Goal:** freeze the wire format and reshape the Mac code so later phases are additive.

Status: `docs/protocol.md`, `docs/pairing-flow.md`, `docs/glossary.md` written;
`mac/ClipSyncMac` refactored into the `mac/ClipSyncCore` package (library +
`clipsync-cli` + tests); dedupe extracted into `ClipboardEventStore`; 12 unit
tests passing (`swift test`).

Tasks:
1. **Write `docs/protocol.md`** — the canonical message spec (see "Protocol v1" below).
2. **Write `docs/pairing-flow.md`** and `docs/glossary.md` (glossary can grow over time).
3. **Refactor `mac/ClipSyncMac` → `mac/ClipSyncCore` package** with a library target:
   - Move `PasteboardWatcher`, `ClipboardNormalizer`, `ClipboardEvent` into `ClipSyncCore`.
   - Keep a tiny `clipsync-cli` executable target that depends on the library (preserves `swift run` dev loop).
   - Add `Tests/ClipSyncCoreTests` with unit tests for normalization + dedupe.

**Acceptance:** `swift test` passes; `swift run clipsync-cli` still prints events;
`docs/protocol.md` describes every message in "Protocol v1".

---

## Phase 1 — Mac menu bar app shell

**Goal:** a real, friction-minimal `.app` the user can run.

Tasks:
1. Create `ClipSyncMac.xcodeproj`, a menu bar (`LSUIElement`) AppKit/SwiftUI app that depends on `ClipSyncCore`.
2. Menu shows: app status, recent-events count, "Quit", and a placeholder "Devices…" item.
3. Wire the `PasteboardWatcher` into the app lifecycle (start on launch, stop on quit).
4. Add **Launch at Login** (`SMAppService`) toggle.
5. Add the **App Sandbox** entitlements needed later: outgoing/incoming network, Bonjour service `_clipsync._tcp`.

**Acceptance:** building the Xcode target produces a menu bar app; copying text
updates the recent-events count; "Launch at Login" works after reboot.

> Note: clipboard read on macOS needs no special permission, but Bonjour +
> network entitlements must be in place now so Phases 2–3 don't get blocked.

---

## Phase 2 — Discovery (Bonjour advertise + Android NSD)

**Goal:** Android finds the Mac automatically.

Mac tasks:
1. `BonjourAdvertiser` in `ClipSyncCore` using `NWListener` with
   `service: NWListener.Service(type: "_clipsync._tcp")`.
2. TXT record: `device_name`, `device_id`, `protocol_version`.
3. Pick a port (let the OS assign; advertise it via Bonjour).

Android tasks (new `android/ClipSyncAndroid` project):
1. Scaffold Kotlin app (single screen + foreground service later).
2. `NsdDiscoveryManager` resolves `_clipsync._tcp`, lists found Macs, picks a target.

**Acceptance:** Android lists the Mac by name on the same Wi-Fi; resolving yields host+port.

---

## Phase 3 — Plaintext transport (prove the pipe, no crypto yet)

**Goal:** Mac → Android `clipboard_update` delivery end to end.

Mac tasks:
1. `WebSocketServer` in `ClipSyncCore` via `NWListener` + `NWProtocolWebSocket.Options`.
2. On `PasteboardWatcher` event → build a **plaintext** `clipboard_update` (no `nonce`/`ciphertext`, just `text`) → send to connected clients.
3. Handle connect/disconnect; log (without dumping clipboard contents at info level).

Android tasks:
1. `ClipSyncWebSocketClient` (OkHttp) connects to the resolved host/port.
2. Parse `clipboard_update`; on receipt, write text to `ClipboardManager` via `ClipboardApplyService`.
3. Send `ack`.

**Acceptance:** copy on Mac → text appears in Android clipboard within ~1s;
duplicates suppressed; `ack` logged on Mac.

> This is the "development shortcut" plaintext path from `BUILD_PLAN.md` §7. It is
> temporary scaffolding; Phase 4 replaces the plaintext body with ciphertext.

---

## Phase 4 — Pairing & encryption

**Goal:** trust + authenticated encryption. Two sub-phases.

### 4a — Numeric SAS pairing + AES-GCM
1. **Identity keys:** each device generates an **X25519** keypair on first run.
   Mac stores private key in **Keychain**; Android in **Keystore**-protected prefs.
2. **Handshake:** `hello` exchanges device id + public key + `protocol_version`.
3. **Key agreement:** X25519 → shared secret → **HKDF** → session key.
4. **SAS:** derive a 6-digit code from a transcript hash of both public keys;
   show on both devices; user taps "Match" to confirm. On confirm, store the
   peer's public key in `TrustedDeviceStore` (Mac Keychain / Android Keystore).
5. **Encrypt payloads:** `clipboard_update` body becomes `AES-256-GCM`
   (`nonce` + `ciphertext`) per the Protocol v1 shape.

### 4b — QR pairing (friction upgrade)
1. Mac renders a QR encoding `{device_id, public_key, protocol_version}`.
2. Android scans (CameraX + MLKit/ZXing), verifies, skips manual code entry.
3. Same trust store + same session-key derivation as 4a.

**Acceptance:** fresh devices pair via 6-digit code; thereafter reconnect without
re-pairing; clipboard payloads are ciphertext on the wire (verify via packet log);
QR pairing completes without typing.

---

## Phase 5 — Reliability & UX

**Goal:** stable enough for daily use.

- Android **reconnect** state machine (Wi-Fi change, app restart, Mac sleep/wake).
- Android **foreground service** + persistent notification so receive keeps working.
- **Echo-suppression** via `origin` device id (prep for bidirectional).
- Mac menu: connected devices, last-synced time, pause toggle, unpair.
- Android: trusted-Mac management, pause toggle.
- Robust **duplicate suppression** across reconnects (event-id + hash cache, both sides).

**Acceptance:** survives Wi-Fi drop, Mac sleep/wake, and app restart without manual
re-pairing; no duplicate floods; user can pause and unpair from the UI.

---

## Phase 6 — Hardening

- Payload **size limits** + chunking decision for large text.
- Clipboard **content filtering** (e.g. optional skip for password-manager content).
- Diagnostics/log levels that never log clipboard contents above debug.
- **Protocol versioning** negotiation in `hello` (reject/upgrade on mismatch).
- Sleep/wake + backgrounding test matrix.

**Acceptance:** documented test matrix passes; oversized payloads handled
gracefully; version mismatch produces a clear `error`, not a crash.

---

## Beyond v1 — the bidirectional / complete-sync roadmap

Enabled cheaply because the protocol is already symmetric:
1. **Android → Mac text:** Android emits `clipboard_update`; Mac applies to
   `NSPasteboard`. Android background clipboard *read* is restricted — solve via a
   share-target / quick-tile / accessibility approach (design spike needed).
2. **Mac ⇄ Mac and multi-device:** `NWBrowser` lets a Mac act as client too; move
   to a small mesh / last-writer-wins with `origin`+`timestamp`.
3. **Rich types:** honor `mimeType` for images (`image/png`) and rich text;
   transfer larger blobs with chunked frames.

---

## Protocol v1 (summary — full text goes in `docs/protocol.md`)

Service: `_clipsync._tcp`. Transport: WebSocket (text frames, UTF-8 JSON).
`protocol_version: 1`.

Messages:
- `hello` — `{ deviceId, deviceName, publicKey, protocolVersion }`
- `pair_request` / `pair_confirm` — SAS/QR pairing handshake
- `clipboard_update` — see shape below
- `ack` — `{ eventId }`
- `ping` / `pong` — keepalive
- `error` — `{ code, message }`

`clipboard_update` (encrypted form, Phase 4+):
```json
{
  "type": "clipboard_update",
  "eventId": "uuid",
  "origin": "sender-device-id",
  "timestamp": 1747440000,
  "mimeType": "text/plain",
  "nonce": "base64-nonce",
  "ciphertext": "base64-ciphertext"
}
```
Phase 3 (plaintext, temporary) replaces `nonce`/`ciphertext` with `"text": "..."`.

---

## Suggested next action

Start **Phase 0**: write `docs/protocol.md`, then refactor `mac/ClipSyncMac`
into the `ClipSyncCore` package + tests. Everything after that is additive.
