# Phase 4a (Mac half) — Crypto Core: Design

Status: **implemented** (this doc is both the design and the cross-platform
contract). Lands in `mac/ClipSyncCore`. No network wiring — see "Deferred".

## Goal

Build the offline-testable security foundation for pairing + encrypted sync:
persistent identity keys, per-connection session encryption, and the SAS pairing
code. Everything here is unit-testable with `swift test` (no phone, no live
socket), and it is the half that is identical regardless of what the ColorOS
background-write question turns out to be — so it is never wasted work.

## Scope (decided)

**Crypto core only.** Build the primitives + wire models as a pure library; stop
before wiring the `hello` handshake / trust gate / encrypted broadcast into the
running `ClipSyncServer` (that can't be end-to-end verified without the Android
peer, and belongs with the on-device work).

## Components (all in `Sources/ClipSyncCore`)

| Unit | Responsibility |
| --- | --- |
| `DeviceKeypair` | X25519 identity keypair; raw 32-byte (de)serialization; `sharedSecret(withPeerPublicKey:)`. |
| `KeyStore` (protocol) + `KeychainKeyStore` + `InMemoryKeyStore` | Secret-storage seam. App → Keychain; tests → in-memory. |
| `PersistentIdentity` | Load-or-create a stable `deviceId` + keypair via a `KeyStore`. Durable replacement for the app's throwaway per-launch `UUID()`. |
| `TrustedDeviceStore` | Paired peers: `deviceId → publicKey` (`trust` / `publicKey(forDeviceId:)` / `isTrusted` / `untrust`). |
| `SessionCrypto` | HKDF session key over the X25519 shared secret; AES-256-GCM `seal`/`open`. |
| `SASCode` | 6-digit pairing code from a sorted transcript of both public keys. |
| `HelloMessage`, `EncryptedClipboardUpdate` | Codable wire models per `docs/protocol.md`. Defined now, not yet sent. |

CryptoKit only (`Curve25519.KeyAgreement`, `HKDF`, `AES.GCM`) — zero third-party
dependencies.

## The cross-platform crypto contract (Android MUST match byte-for-byte)

- **Public keys on the wire:** raw 32-byte X25519 keys, standard base64 (padded),
  in `hello.publicKey`.
- **Session key:**
  `HKDF-SHA256(ikm = X25519(ourPriv, theirPub), salt = <empty>, info = "clipsync-session-v1", L = 32)`.
- **Payload encryption:** AES-256-GCM, fresh random **12-byte** nonce per message.
  Wire `nonce` = base64(nonce); wire `ciphertext` = base64(ciphertext ‖ 16-byte GCM tag).
- **SAS code:**
  1. Sort the two raw 32-byte public keys by their bytes; concatenate → 64-byte transcript.
  2. `HKDF-SHA256(ikm = transcript, salt = <empty>, info = "clipsync-sas", L = 4)`.
  3. Read the 4 bytes big-endian as `UInt32`, `% 1_000_000`, zero-pad to 6 digits.
- **No forward secrecy in v1** (session key derives directly from long-term keys);
  the ephemeral-DH upgrade is a later hardening item and changes no message shapes.

### Known-answer vectors (pinned in tests)

Fixed inputs the Android implementation can check against:

- `keyA = bytes 0x00…0x1f`, `keyB = bytes 0xff…0xe0` → **SAS = `064987`**.
- `macPriv = bytes 0x00…0x1f`, `phonePriv = bytes 0x40…0x5f` →
  session key = `a0fe1886b3d80ff6abb9eb4540031af4e512c167c3c819fb97fcb576b2738a1a`.

## Testing

21 tests (offline, `swift test`): keypair sizes + round-trip + agreement symmetry;
session key agreement + seal/open round-trip + fresh-nonce + tamper-fails +
wrong-key-fails + malformed-input; SAS 6-digit + order-independence + KAT;
identity idempotency + fresh-differs; trust round-trip; wire-model JSON shapes +
encrypted-update decrypts on the peer. `KeychainKeyStore` is intentionally not
exercised under `swift test` (no entitlements); its logic is thin and the
behaviour is covered via `InMemoryKeyStore`.

## Deferred (next steps, not in this chunk)

- **Live wiring:** exchange `hello`, gate on `TrustedDeviceStore`, derive
  `SessionCrypto` per connection, broadcast `EncryptedClipboardUpdate` instead of
  plaintext, and switch `AppDelegate` from its throwaway `UUID()` to
  `PersistentIdentity(keyStore: KeychainKeyStore())`. Verify against the phone.
- **Pairing UX** (SAS match screen on both devices) and **QR** (Phase 4b).
- **Android crypto** implementing this exact contract (Keystore + the vectors above).
