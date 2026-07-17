import Foundation
import Testing
@testable import ClipSyncCore

@Suite("SessionCrypto — HKDF session key + AES-256-GCM")
struct SessionCryptoTests {

    /// Two sessions derived from the same pair of devices — one per side.
    private func sessions() throws -> (mac: SessionCrypto, phone: SessionCrypto) {
        let mac = DeviceKeypair()
        let phone = DeviceKeypair()
        return (
            try SessionCrypto(ourKeypair: mac, peerPublicKey: phone.publicKeyRaw),
            try SessionCrypto(ourKeypair: phone, peerPublicKey: mac.publicKeyRaw)
        )
    }

    @Test("both peers derive the same 32-byte session key")
    func sameKey() throws {
        let s = try sessions()
        #expect(s.mac.keyData == s.phone.keyData)
        #expect(s.mac.keyData.count == 32)
    }

    @Test("text sealed on one side opens on the other")
    func roundTrip() throws {
        let s = try sessions()
        let sealed = try s.mac.seal("hello 🌍 from the Mac — line1\nline2")
        let opened = try s.phone.open(nonce: sealed.nonce, ciphertext: sealed.ciphertext)
        #expect(opened == "hello 🌍 from the Mac — line1\nline2")
    }

    @Test("a fresh nonce is used per message (no ciphertext reuse)")
    func freshNonce() throws {
        let s = try sessions()
        let a = try s.mac.seal("same text")
        let b = try s.mac.seal("same text")
        #expect(a.nonce != b.nonce)
        #expect(a.ciphertext != b.ciphertext)
    }

    @Test("tampered ciphertext fails the GCM tag")
    func tamperFails() throws {
        let s = try sessions()
        let sealed = try s.mac.seal("secret")
        var raw = Data(base64Encoded: sealed.ciphertext)!
        raw[0] ^= 0xFF
        #expect(throws: (any Error).self) {
            _ = try s.phone.open(nonce: sealed.nonce, ciphertext: raw.base64EncodedString())
        }
    }

    @Test("a stranger's session key cannot open the message")
    func wrongKeyFails() throws {
        let s = try sessions()
        let stranger = try SessionCrypto(ourKeypair: DeviceKeypair(), peerPublicKey: DeviceKeypair().publicKeyRaw)
        let sealed = try s.mac.seal("secret")
        #expect(throws: (any Error).self) {
            _ = try stranger.open(nonce: sealed.nonce, ciphertext: sealed.ciphertext)
        }
    }

    @Test("malformed base64 is rejected, not crashed")
    func malformedInput() throws {
        let s = try sessions()
        #expect(throws: (any Error).self) {
            _ = try s.mac.open(nonce: "!!!not base64!!!", ciphertext: "also-not")
        }
    }

    @Test("session-key known-answer vector (the contract with Android)")
    func sessionKeyVector() throws {
        // Fixed private keys → the derived session key must never drift. The
        // Android session-key derivation must reproduce this exact hex.
        let mac = try DeviceKeypair(rawPrivateKey: Data((0..<32).map { UInt8($0) }))
        let phone = try DeviceKeypair(rawPrivateKey: Data((0..<32).map { UInt8(64 + $0) }))
        let session = try SessionCrypto(ourKeypair: mac, peerPublicKey: phone.publicKeyRaw)
        let hex = session.keyData.map { String(format: "%02x", $0) }.joined()
        #expect(hex == "a0fe1886b3d80ff6abb9eb4540031af4e512c167c3c819fb97fcb576b2738a1a")
    }
}
