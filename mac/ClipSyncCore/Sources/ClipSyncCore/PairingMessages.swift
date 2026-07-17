import Foundation

/// The `hello` message (see `docs/protocol.md` § hello). Both peers send it right
/// after the socket opens; it carries the sender's public key, which feeds both
/// pairing (SAS) and per-connection session-key derivation.
public struct HelloMessage: Codable, Equatable {
    public let type: String
    public let deviceId: String
    public let deviceName: String
    /// base64 of the raw 32-byte X25519 public key.
    public let publicKey: String
    public let protocolVersion: Int

    public init(
        deviceId: String,
        deviceName: String,
        publicKey: String,
        protocolVersion: Int = ClipSyncProtocol.version
    ) {
        self.type = "hello"
        self.deviceId = deviceId
        self.deviceName = deviceName
        self.publicKey = publicKey
        self.protocolVersion = protocolVersion
    }

    public func jsonData() throws -> Data { try JSONEncoder().encode(self) }

    public static func decode(_ data: Data) throws -> HelloMessage {
        try JSONDecoder().decode(HelloMessage.self, from: data)
    }
}

/// The **encrypted** form of `clipboard_update` (see `docs/protocol.md`,
/// Phase 4+). Same envelope as the plaintext `ClipboardUpdateMessage`, but the
/// body is `nonce` + `ciphertext` (AES-256-GCM) instead of `text`.
public struct EncryptedClipboardUpdate: Codable, Equatable {
    public let type: String
    public let eventId: String
    public let origin: String
    public let timestamp: Int
    public let mimeType: String
    public let nonce: String
    public let ciphertext: String

    public init(
        eventId: String,
        origin: String,
        timestamp: Int,
        mimeType: String = "text/plain",
        nonce: String,
        ciphertext: String
    ) {
        self.type = "clipboard_update"
        self.eventId = eventId
        self.origin = origin
        self.timestamp = timestamp
        self.mimeType = mimeType
        self.nonce = nonce
        self.ciphertext = ciphertext
    }

    /// Builds an encrypted update for a clipboard event, sealing the copied text
    /// under the connection's session key.
    public init(event: ClipboardEvent, origin: String, session: SessionCrypto) throws {
        let sealed = try session.seal(event.text)
        self.init(
            eventId: event.id.uuidString,
            origin: origin,
            timestamp: Int(event.timestamp.timeIntervalSince1970),
            nonce: sealed.nonce,
            ciphertext: sealed.ciphertext
        )
    }

    public func jsonData() throws -> Data { try JSONEncoder().encode(self) }
}
