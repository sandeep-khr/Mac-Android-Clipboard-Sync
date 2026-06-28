# Pairing & Trust Flow

Pairing answers one question: *is this Mac and this phone allowed to talk to each
other, and is the connection free of a man-in-the-middle?*

We use **X25519** identity keys plus a user-verified short code (SAS) or QR scan.
Encryption alone is not enough — without verification, an attacker on the LAN
could impersonate either side. The SAS/QR step is what authenticates the keys.

## Identity keys

On first launch each device generates a long-term **X25519** keypair.

- **Mac:** private key stored in the **Keychain** (not user-readable).
- **Android:** private key stored in **Keystore**-backed encrypted prefs.
- The public key travels in the `hello` message.

A device id (UUID) is generated once and persisted alongside the key.

## First-time pairing (SAS — Phase 4a)

1. Android discovers and connects to the Mac; both send `hello` (exchanging
   public keys).
2. Because the peer is not yet in the trust store, Android sends `pair_request`
   with `method: "sas"`.
3. **Both** devices compute a short authentication string:
   - `transcript = sort(macPublicKey, androidPublicKey)` (sorted so both sides
     hash the same bytes in the same order)
   - `code = first 6 decimal digits of HKDF(transcript, info="clipsync-sas")`
4. Each device shows the 6-digit code. The user confirms they match and taps
   **Match** on both.
5. On confirmation, each device stores the peer's public key + device id in its
   `TrustedDeviceStore` and replies `pair_confirm { accepted: true }`.
6. The connection proceeds to encrypted `clipboard_update`s.

If the codes do not match, the user taps **Don't match** → `pair_confirm
{ accepted: false }` → connection closed, nothing stored.

## First-time pairing (QR — Phase 4b)

A lower-friction alternative to typing/comparing digits:

1. The Mac renders a QR encoding `{ deviceId, publicKey, protocolVersion }`.
2. Android scans it (CameraX + ZXing/MLKit), obtaining the Mac's public key
   out-of-band — which authenticates it directly.
3. Android stores the Mac in its trust store and sends `pair_request`
   /`pair_confirm`; the Mac confirms the reciprocal key.

QR and SAS share the same trust store and the same session-key derivation; only
the *authentication* step differs.

## Session keys

Pairing establishes *trust*. Each **connection** derives a fresh session key:

1. Both sides already have the peer's long-term public key (from trust store).
2. `sharedSecret = X25519(ourPrivate, theirPublic)`.
3. `sessionKey = HKDF-SHA256(sharedSecret, info="clipsync-session-v1", salt=...)`.
4. `clipboard_update` payloads are sealed with **AES-256-GCM** under `sessionKey`,
   a fresh 96-bit `nonce` per message.

> For true forward secrecy we could add an ephemeral X25519 exchange per session.
> v1 derives directly from the long-term keys; the ephemeral upgrade is a
> hardening item and does not change the message shapes.

## Reconnection

Once paired, reconnection is silent: discover → connect → `hello` → recognize the
peer in the trust store → derive session key → resume. No user interaction.

## Unpairing

Removing a device from the `TrustedDeviceStore` (via the UI) forces a fresh SAS/QR
pairing next time. Useful if a phone is lost or keys should be rotated.
