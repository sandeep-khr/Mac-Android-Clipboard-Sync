import Foundation
import Testing
@testable import ClipSyncCore

@Suite("clipboard_update message encoding")
struct ClipboardUpdateMessageTests {

    private func event(text: String) -> ClipboardEvent {
        ClipboardEvent(
            id: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
            timestamp: Date(timeIntervalSince1970: 1_747_440_000),
            text: text,
            normalizedText: ClipboardNormalizer.normalize(text),
            hash: ClipboardNormalizer.hash(ClipboardNormalizer.normalize(text))
        )
    }

    /// Decodes the JSON the server puts on the wire so we assert on the real bytes.
    private func decode(_ data: Data) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test("carries the protocol fields for a plaintext update")
    func plaintextFields() throws {
        let message = ClipboardUpdateMessage(event: event(text: "hello world"), origin: "mac-device-1")
        let json = try decode(try message.jsonData())

        #expect(json["type"] as? String == "clipboard_update")
        #expect(json["eventId"] as? String == "11111111-2222-3333-4444-555555555555")
        #expect(json["origin"] as? String == "mac-device-1")
        #expect(json["mimeType"] as? String == "text/plain")
        #expect(json["timestamp"] as? Int == 1_747_440_000)
        #expect(json["text"] as? String == "hello world")
    }

    @Test("sends the copied text faithfully, including internal whitespace")
    func faithfulText() throws {
        let message = ClipboardUpdateMessage(event: event(text: "  spaced  out  "), origin: "m")
        let json = try decode(try message.jsonData())
        #expect(json["text"] as? String == "  spaced  out  ")
    }

    @Test("plaintext form does not include encryption fields (Phase 3)")
    func noCryptoFields() throws {
        let message = ClipboardUpdateMessage(event: event(text: "x"), origin: "m")
        let json = try decode(try message.jsonData())
        #expect(json["nonce"] == nil)
        #expect(json["ciphertext"] == nil)
    }
}
