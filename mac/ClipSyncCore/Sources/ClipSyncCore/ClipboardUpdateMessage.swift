import Foundation

/// A `clipboard_update` message in its **plaintext** form (Phase 3), per
/// `docs/protocol.md`. Phase 4 replaces `text` with `nonce` + `ciphertext`.
public struct ClipboardUpdateMessage: Codable, Equatable {
    public let type: String
    public let eventId: String
    public let origin: String
    public let timestamp: Int
    public let mimeType: String
    public let text: String

    /// Builds a plaintext update for a clipboard event.
    /// - Parameter origin: the sending device's id (used for echo-suppression
    ///   once sync becomes bidirectional).
    public init(event: ClipboardEvent, origin: String) {
        self.type = "clipboard_update"
        self.eventId = event.id.uuidString
        self.origin = origin
        self.timestamp = Int(event.timestamp.timeIntervalSince1970)
        self.mimeType = "text/plain"
        // Send the copied text faithfully (not the normalized/trimmed form) so
        // the pasted result matches what the user copied.
        self.text = event.text
    }

    public func jsonData() throws -> Data {
        try JSONEncoder().encode(self)
    }
}
