# Security Policy

ClipSync moves clipboard contents between devices, so security matters. If you
find a vulnerability, please **don't open a public issue** — instead use GitHub's
[private vulnerability reporting](../../security/advisories/new) (Security →
Report a vulnerability) so it can be fixed before disclosure.

## What's in place

- Clipboard payloads are encrypted end-to-end with **AES-256-GCM**, keyed via
  **X25519** key agreement + **HKDF-SHA256** (see `docs/pairing-flow.md`).
- Traffic never leaves the local network — no cloud, no relay server.

## Known limitations (v0.1.x)

- **No trust gate yet.** Devices are trusted on first connection (TOFU); any
  device on the same LAN that speaks the protocol can pair. A SAS/QR pairing
  confirmation is [tracked](../../issues) but not implemented — treat this as a
  home-network tool for now, not something to run on untrusted Wi-Fi.
- Identity keys are currently ephemeral per launch.

These are intentional, documented gaps for an early release, not something to
report as a vulnerability — but thoughts on the pairing design are welcome.
