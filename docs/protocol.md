# ClipSync Protocol v1

This is the canonical wire spec. Both the Mac and Android apps MUST agree on it.
If you change a message shape, bump `protocolVersion` and update this file.

## Layers

| Concern | Mechanism |
| --- | --- |
| Discovery | Bonjour (macOS) / NSD (Android), service type `_clipsync._tcp` |
| Transport | WebSocket over TCP, UTF-8 JSON text frames |
| Trust | X25519 identity keys + SAS/QR pairing |
| Confidentiality | AES-256-GCM with HKDF-derived session keys |

`protocolVersion` for this document is **1**.

## Discovery

The Mac advertises a Bonjour service:

- **Service type:** `_clipsync._tcp`
- **Port:** chosen by the Mac (OS-assigned, advertised via Bonjour)
- **TXT record fields:**
  - `device_name` — human-readable, e.g. "Sandeep's MacBook"
  - `device_id` — stable UUID for this Mac install
  - `protocol_version` — `1`

Android resolves the service to obtain host + port, then opens a WebSocket.

## Connection lifecycle

```
Android                                   Mac
  | --- WebSocket connect --------------->  |
  | --- hello -------------------------->   |
  | <-- hello ---------------------------   |
  | (if not yet trusted) pair_request <-->  |   # SAS or QR, see pairing-flow.md
  | <-- clipboard_update ----------------   |   # Mac emits as text is copied
  | --- ack --------------------------->    |
  | <-- ping / --- pong --------------->    |   # keepalive
```

In v1 only the Mac emits `clipboard_update`. The protocol is symmetric, so a
future Android → Mac direction reuses the same message with `origin` set to the
Android device id.

## Message envelope

Every message is a JSON object with a `type` field. Unknown `type` values MUST be
ignored (forward compatibility), except during `hello` version negotiation.

### `hello`

Sent by both peers immediately after the socket opens.

```json
{
  "type": "hello",
  "deviceId": "uuid",
  "deviceName": "Sandeep's MacBook",
  "publicKey": "base64-x25519-public-key",
  "protocolVersion": 1
}
```

If `protocolVersion` is incompatible, the receiver sends `error` with
`code: "version_mismatch"` and closes.

### `pair_request` / `pair_confirm`

Used the first time two devices meet. Full handshake in `docs/pairing-flow.md`.

```json
{ "type": "pair_request", "deviceId": "uuid", "method": "sas" }
{ "type": "pair_confirm", "deviceId": "uuid", "accepted": true }
```

`method` is `"sas"` (6-digit code) or `"qr"`.

### `clipboard_update`

The core payload. Two forms.

**Encrypted (Phase 4+, the real form):**

```json
{
  "type": "clipboard_update",
  "eventId": "uuid",
  "origin": "sender-device-id",
  "timestamp": 1747440000,
  "mimeType": "text/plain",
  "nonce": "base64-12-byte-nonce",
  "ciphertext": "base64-aes-256-gcm-output"
}
```

**Plaintext (Phase 3 only, temporary scaffolding):**

```json
{
  "type": "clipboard_update",
  "eventId": "uuid",
  "origin": "sender-device-id",
  "timestamp": 1747440000,
  "mimeType": "text/plain",
  "text": "the copied text"
}
```

Field notes:
- `eventId` — UUID; receivers dedupe on this to ignore replays.
- `origin` — device id of the sender; used for echo-suppression once sync is
  bidirectional (never apply an update whose `origin` is yourself).
- `mimeType` — only `text/plain` is honored in v1; field exists so images/rich
  text can be added without a protocol bump.
- `nonce` — 96-bit GCM nonce, unique per message under a given session key.
- `ciphertext` — AES-256-GCM encryption of the UTF-8 clipboard bytes; the GCM
  tag is appended (standard CryptoKit `SealedBox.combined` layout minus nonce).

### `ack`

```json
{ "type": "ack", "eventId": "uuid" }
```

### `ping` / `pong`

```json
{ "type": "ping", "timestamp": 1747440000 }
{ "type": "pong", "timestamp": 1747440000 }
```

Keepalive; also used to detect dead connections for reconnect logic.

### `error`

```json
{ "type": "error", "code": "version_mismatch", "message": "human readable" }
```

Defined codes: `version_mismatch`, `not_paired`, `decrypt_failed`,
`payload_too_large`, `malformed`.

## Duplicate suppression

Two independent layers:
1. **Sender side** — do not emit a `clipboard_update` if the normalized content
   hash matches the previously sent one (already implemented in the Mac watcher).
2. **Receiver side** — keep a bounded cache of recently seen `eventId`s and
   content hashes; ignore an update already applied.

## Versioning

`protocolVersion` is exchanged in `hello`. v1 rule: equal versions proceed;
unequal versions reject with `version_mismatch`. A future negotiation scheme can
relax this to "lowest common supported version".
