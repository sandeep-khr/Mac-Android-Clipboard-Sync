# Glossary

Plain-language definitions for the concepts this project uses. Grows as we build.

### API
The interface a platform gives your code. `NSPasteboard` is a macOS API for
clipboard access; Android's `ClipboardManager` is its counterpart.

### Framework
A larger set of tools and structure for building part of an app — e.g. `AppKit`
for Mac UI, `Network.framework` for networking, the Android SDK.

### Bonjour / NSD
Zero-configuration service discovery. Bonjour (Apple) and NSD (Android) let
devices find each other on a LAN without knowing IP addresses in advance.

### WebSocket
A transport that keeps a single TCP connection open for ongoing two-way
messaging — cheaper than re-connecting for every small message.

### Protocol
The agreed rules for communication: which messages exist, their fields, their
order, and how errors/reconnects are handled. See `protocol.md`.

### Transport
The channel that carries messages. Here it's WebSocket.

### Handshake
The first exchange between two devices to establish rules or trust — here, the
`hello` message exchange.

### Pairing
Recording that two specific devices are allowed to talk in the future. See
`pairing-flow.md`.

### Identity key / keypair
A long-term public/private key pair that identifies a device. The public half is
shared; the private half never leaves the device.

### X25519
A modern key-agreement algorithm: two devices combine their own private key with
the peer's public key to derive the same shared secret, without sending it.

### HKDF
A key-derivation function that turns raw shared-secret material into properly
sized, purpose-bound encryption keys.

### AES-256-GCM
An authenticated encryption mode: provides both confidentiality (can't read it)
and integrity (can't tamper with it undetected).

### SAS (Short Authentication String)
A short human-comparable code derived from both public keys. If both screens show
the same code, there's no man-in-the-middle.

### Nonce
A "number used once" — unique per encrypted message so identical plaintexts don't
produce identical ciphertexts.

### ACK
Acknowledgment: "I received your message."

### Payload
The useful content inside a message — here, the clipboard text.

### Polling
Checking something repeatedly on a schedule. The watcher polls
`NSPasteboard.changeCount` every 0.4s.

### Normalization
Converting input to a consistent form before comparing/hashing — here: CRLF→LF
and trimming whitespace.

### Hash
A fixed-size fingerprint of data, used to compare clipboard contents quickly.

### changeCount
A macOS counter `NSPasteboard` increments on every clipboard change. Comparing it
to the last seen value is how we detect "something was copied".

### Echo-suppression
Once sync is bidirectional, the rule that a device never re-applies an update it
originated — preventing A→B→A loops. Implemented via the `origin` field.
