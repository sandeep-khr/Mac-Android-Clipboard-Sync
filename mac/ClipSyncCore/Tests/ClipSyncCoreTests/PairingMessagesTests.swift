import Foundation
import Testing
@testable import ClipSyncCore

@Suite("Pairing & encrypted wire messages")
struct PairingMessagesTests {

    private func decode(_ data: Data) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func event(text: String) -> ClipboardEvent {
        ClipboardEvent(
            id: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
            timestamp: Date(timeIntervalSince1970: 1_747_440_000),
            text: text,
            normalizedText: ClipboardNormalizer.normalize(text),
            hash: ClipboardNormalizer.hash(ClipboardNormalizer.normalize(text))
        )
    }

    @Test("hello carries the protocol fields")
    func helloFields() throws {
        let hello = HelloMessage(deviceId: "mac-1", deviceName: "Sandeep's MacBook", publicKey: "BASE64KEY")
        let json = try decode(try hello.jsonData())
        #expect(json["type"] as? String == "hello")
        #expect(json["deviceId"] as? String == "mac-1")
        #expect(json["deviceName"] as? String == "Sandeep's MacBook")
        #expect(json["publicKey"] as? String == "BASE64KEY")
        #expect(json["protocolVersion"] as? Int == 1)
    }

    @Test("hello round-trips through Codable")
    func helloRoundTrip() throws {
        let hello = HelloMessage(deviceId: "mac-1", deviceName: "Mac", publicKey: "k")
        #expect(try HelloMessage.decode(try hello.jsonData()) == hello)
    }

    @Test("encrypted clipboard_update carries ciphertext, never plaintext text")
    func encryptedFields() throws {
        let mac = DeviceKeypair()
        let phone = DeviceKeypair()
        let macSession = try SessionCrypto(ourKeypair: mac, peerPublicKey: phone.publicKeyRaw)

        let msg = try EncryptedClipboardUpdate(event: event(text: "secret text"), origin: "mac-1", session: macSession)
        let json = try decode(try msg.jsonData())

        #expect(json["type"] as? String == "clipboard_update")
        #expect(json["eventId"] as? String == "11111111-2222-3333-4444-555555555555")
        #expect(json["origin"] as? String == "mac-1")
        #expect(json["mimeType"] as? String == "text/plain")
        #expect(json["timestamp"] as? Int == 1_747_440_000)
        // The whole point: no cleartext on the wire.
        #expect(json["text"] == nil)
        #expect(json["nonce"] as? String != nil)
        #expect(json["ciphertext"] as? String != nil)
    }

    @Test("the peer decrypts an encrypted clipboard_update back to the original text")
    func decryptsOnPeer() throws {
        let mac = DeviceKeypair()
        let phone = DeviceKeypair()
        let macSession = try SessionCrypto(ourKeypair: mac, peerPublicKey: phone.publicKeyRaw)
        let phoneSession = try SessionCrypto(ourKeypair: phone, peerPublicKey: mac.publicKeyRaw)

        let msg = try EncryptedClipboardUpdate(event: event(text: "  spaced  out  "), origin: "mac-1", session: macSession)
        let opened = try phoneSession.open(nonce: msg.nonce, ciphertext: msg.ciphertext)
        #expect(opened == "  spaced  out  ")
    }
}
