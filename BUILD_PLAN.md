# Mac ↔ Android Clipboard Sync Build Plan

## 1. Product Goal

Build a private clipboard sync system that sends copied text from a Mac to an Android phone over local Wi-Fi.

For the first version, we are intentionally narrowing scope:

- Direction: Mac -> Android only
- Data type: `text/plain` only
- Network: local Wi-Fi only
- Accounts: none
- Cloud services: none
- Discovery: Bonjour / NSD
- Transport: WebSocket
- Security: end-to-end encrypted application messages

This first slice proves the hardest foundation pieces:

- device discovery
- network connection
- pairing and trust
- encryption
- clipboard watching
- clipboard application on Android

Once this works well, we can design Android -> Mac sync as a second phase.

## 2. Why We Are Starting With Mac -> Android

This direction is the safest and fastest path to a working product.

- On macOS, clipboard watching is straightforward with `NSPasteboard`.
- On Android, receiving clipboard data is easier than reading clipboard data in the background.
- Modern Android versions restrict clipboard reads unless the app is in focus or acting as the default keyboard.

That means Mac -> Android is the cleanest place to begin.

## 3. Version 1 Success Criteria

Version 1 is successful when all of these are true:

1. The Mac app detects when the user copies plain text.
2. The Android app automatically finds the Mac on the same Wi-Fi network.
3. The two devices can pair securely.
4. Clipboard data is sent over a persistent local connection.
5. The Android app updates the phone clipboard automatically.
6. Duplicate copies do not spam the phone repeatedly.
7. The connection recovers after Wi-Fi reconnects or brief app restarts.

## 4. High-Level Architecture

### Mac Side

The Mac app will be a menu bar app built with Swift and AppKit.

Responsibilities:

- watch the system clipboard
- host a local WebSocket server
- advertise the service with Bonjour
- encrypt outgoing messages
- manage device pairing
- remember trusted Android devices

### Android Side

The Android app will be built with Kotlin.

Responsibilities:

- discover the Mac app using NSD
- connect to the Mac over WebSocket
- perform pairing and trust checks
- decrypt incoming messages
- update the Android clipboard
- reconnect when the network changes

## 5. Connection Model

We will make the Mac the server and Android the client.

Why:

- the Mac is more likely to stay awake and connected on the LAN
- Bonjour service advertisement is natural from the Mac side
- Android is better positioned as a reconnecting client

Flow:

1. Mac starts local server on a chosen TCP port.
2. Mac advertises `_clipsync._tcp` over Bonjour.
3. Android discovers the service using NSD.
4. Android opens a WebSocket connection to the Mac.
5. The devices exchange handshake and trust information.
6. The Mac sends encrypted clipboard events as they happen.

## 6. Protocol Design

### What "Protocol" Means

A protocol is the set of rules both sides agree on for communication.

It defines:

- what messages exist
- what fields each message contains
- what order messages are sent in
- how errors and reconnects are handled

Think of it as the shared language spoken by both apps.

### Transport Protocol

We will use WebSocket as the transport layer.

Why WebSocket:

- keeps one persistent connection open
- reduces repeated connection setup cost
- works well for small real-time messages
- easy to model as event-based communication

### Discovery Protocol

We will use Bonjour on macOS and NSD on Android.

This is not the main message transport. It is only for finding devices on the local network.

Bonjour advertisement example:

- service type: `_clipsync._tcp`
- port: chosen by Mac server
- TXT fields:
  - `device_name`
  - `device_id`
  - `protocol_version`

### Application Message Types

Initial protocol messages:

- `hello`
- `pair_request`
- `pair_confirm`
- `clipboard_update`
- `ack`
- `ping`
- `error`

Example shape:

```json
{
  "type": "clipboard_update",
  "eventId": "uuid",
  "timestamp": 1747440000,
  "mimeType": "text/plain",
  "nonce": "base64-nonce",
  "ciphertext": "base64-ciphertext"
}
```

## 7. Security Design

### What "End-to-End Encrypted" Means Here

End-to-end encryption means the clipboard content is encrypted by the sender app and only decrypted by the receiver app.

Even though the traffic travels over local Wi-Fi, we do not trust the network itself.

### Recommended Security Model

Use a two-step model:

1. Pair devices once
2. Derive session keys for message encryption

Planned approach:

- each device generates a long-term key pair
- pairing uses a short verification code or QR code
- trusted device identity is stored locally
- each connection derives a fresh shared secret
- clipboard payloads are encrypted with `AES-256-GCM`

### Terms

`X25519`
: a modern key agreement method used to derive a shared secret

`HKDF`
: a key derivation function that turns shared secret material into usable encryption keys

`AES-256-GCM`
: an authenticated encryption mode that provides confidentiality and tamper detection

### Development Shortcut

During early local development, we may temporarily use a simpler shared secret just to prove the network path.

But the design target should stay the same: real pairing plus authenticated encryption.

## 8. Clipboard Event Flow

When the user copies text on the Mac:

1. `PasteboardWatcher` notices `changeCount` changed.
2. The app reads plain text from the clipboard.
3. The text is normalized.
4. The app checks whether it is a duplicate of a recent event.
5. A new clipboard event object is created.
6. The payload is encrypted.
7. The message is sent over WebSocket.
8. Android decrypts the payload.
9. Android writes the text into its clipboard.
10. Android sends an `ack`.

## 9. Duplicate Prevention

If a user copies the exact same text many times, we do not want to flood the phone.

We will keep a recent cache of:

- event IDs
- content hashes

Rules:

- if clipboard text did not meaningfully change, skip send
- if the same event was already delivered, ignore replay
- if the same content was sent very recently, optionally suppress it

## 10. Proposed Mac Modules

### `PasteboardWatcher`

Polls `NSPasteboard.general.changeCount` and reads clipboard strings.

### `ClipboardNormalizer`

Normalizes content before hashing and sending.

Examples:

- trim unsupported formats
- convert clipboard input to plain text only

### `ClipboardEventStore`

Tracks recent hashes and event IDs to reduce duplicate sends.

### `BonjourAdvertiser`

Publishes the local service on the LAN.

### `WebSocketServer`

Accepts Android client connections and sends events.

### `CryptoManager`

Handles pairing, key derivation, encryption, and decryption.

### `TrustedDeviceStore`

Stores trusted device records, likely using Keychain-backed storage.

## 11. Proposed Android Modules

### `NsdDiscoveryManager`

Finds the Mac service on local Wi-Fi.

### `ClipSyncWebSocketClient`

Maintains the WebSocket connection and reconnect logic.

### `CryptoManager`

Performs key handling, decryption, and verification.

### `ClipboardApplyService`

Writes received text into the Android clipboard.

### `TrustedDeviceStore`

Stores trusted Mac identities, likely backed by Android Keystore plus local preferences.

## 12. Suggested Repository Structure

```text
Mac-Android-Clipboard-Sync/
├── README.md
├── BUILD_PLAN.md
├── docs/
│   ├── protocol.md
│   ├── pairing-flow.md
│   └── glossary.md
├── mac/
│   └── ClipSyncMac/
└── android/
    └── ClipSyncAndroid/
```

We do not need to create all of this immediately. This is the target shape.

## 13. Implementation Phases

### Phase 0: Planning and Spec

Deliverables:

- build plan
- protocol draft
- pairing design
- repo structure decisions

### Phase 1: Mac Clipboard Watcher

Goal:

Detect Mac clipboard changes locally.

Deliverables:

- menu bar app shell
- `NSPasteboard` watcher
- local logs for copied text

### Phase 2: Android Discovery

Goal:

Find the Mac automatically on the same Wi-Fi.

Deliverables:

- Android app shell
- NSD discovery
- service resolution and connection target selection

### Phase 3: Plaintext Transport

Goal:

Prove Mac -> Android message delivery before adding crypto.

Deliverables:

- working WebSocket server on Mac
- working WebSocket client on Android
- simple plaintext `clipboard_update` messages

### Phase 4: Encryption and Pairing

Goal:

Protect messages and establish trust.

Deliverables:

- device identity generation
- pairing flow
- key storage
- encrypted message payloads

### Phase 5: Reliability and UX

Goal:

Make the system stable enough for daily use.

Deliverables:

- reconnect logic
- duplicate suppression
- simple status UI
- error handling
- trusted device management

### Phase 6: Hardening

Goal:

Prepare for real-world use and later Android -> Mac work.

Deliverables:

- logs and diagnostics
- payload size limits
- clipboard content filtering
- sleep and wake testing
- protocol versioning

## 14. Tools We Expect to Use

### Mac Development Tools

- `Xcode`
- `Swift`
- `AppKit`
- `Network.framework` or a WebSocket library if needed
- `CryptoKit`

### Android Development Tools

- `Android Studio`
- `Kotlin`
- Android `ClipboardManager`
- Android NSD APIs
- Android keystore APIs
- `OkHttp` WebSocket support or similar

### Team / Build Tools

- `git` for version control
- GitHub for backup and collaboration
- Markdown docs for specs

## 15. Programming Terms, Explained Simply

### API

An API is the interface a tool or platform gives us so our code can use it.

Example:

- `NSPasteboard` is a macOS API for clipboard access.

### Framework

A framework is a larger set of tools and structure for building part of an app.

Examples:

- `AppKit` for Mac desktop UI
- Android SDK for Android apps

### Protocol

A protocol is a formal agreement on how two systems communicate.

In this project, our custom message format is part of the protocol.

### Transport

Transport is the channel that carries our messages.

In this project, WebSocket is the transport.

### Discovery

Discovery is how devices find each other automatically on a network.

In this project, Bonjour / NSD handles discovery.

### Handshake

A handshake is the first exchange between two devices to establish communication rules or trust.

### Pairing

Pairing is the process of saying, "this Mac and this phone are allowed to talk to each other in the future."

### Encryption

Encryption turns readable data into protected data so outsiders cannot understand it.

### Authentication

Authentication proves who the other device is.

Encryption alone is not enough if we cannot confirm identity.

### ACK

An ACK is an acknowledgment message that says, "I received your message."

### Payload

The payload is the actual useful content inside a message.

In our case, the clipboard text becomes the payload.

### Client and Server

- Server: waits for connections
- Client: initiates the connection

In Version 1:

- Mac = server
- Android = client

## 16. Risks and Open Questions

Open questions we still need to settle:

1. Which WebSocket implementation is best on the Mac side?
2. Do we want QR pairing, numeric code pairing, or both?
3. Should the Mac sync all copied text, or allow an exclude list later?
4. Should we suppress obviously sensitive clipboard content in Version 1?
5. How much local logging is acceptable for debugging without exposing clipboard contents?

## 17. Recommended Next Steps

Immediate next work:

1. Create `docs/protocol.md` with the first message spec.
2. Create the Mac app shell.
3. Implement and test the Mac pasteboard watcher.
4. Scaffold the Android app.
5. Implement Android NSD discovery.

## 18. Teaching Plan While We Build

As we continue, we should treat the project as both product work and a learning path.

At each implementation step, we will explain:

- what the component does
- why we chose that tool or API
- what tradeoffs it has
- what beginner-to-intermediate programming concept it teaches

Examples:

- while building the watcher, we will cover polling, events, and state change detection
- while building the WebSocket layer, we will cover client/server networking
- while building pairing, we will cover public-key cryptography and key storage
- while building reconnect logic, we will cover resilience and state machines

This way the codebase becomes both a product and a guided systems-programming exercise.
