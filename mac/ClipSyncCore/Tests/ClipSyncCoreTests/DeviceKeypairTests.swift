import Foundation
import CryptoKit
import Testing
@testable import ClipSyncCore

@Suite("DeviceKeypair — X25519 identity keys")
struct DeviceKeypairTests {

    @Test("raw public and private keys are 32 bytes")
    func rawSizes() {
        let kp = DeviceKeypair()
        #expect(kp.privateKeyRaw.count == 32)
        #expect(kp.publicKeyRaw.count == 32)
    }

    @Test("survives a serialize / deserialize round-trip")
    func roundTrip() throws {
        let kp = DeviceKeypair()
        let restored = try DeviceKeypair(rawPrivateKey: kp.privateKeyRaw)
        #expect(restored.publicKeyRaw == kp.publicKeyRaw)
        #expect(restored.privateKeyRaw == kp.privateKeyRaw)
    }

    @Test("rejects a malformed private key")
    func rejectsGarbage() {
        #expect(throws: (any Error).self) {
            _ = try DeviceKeypair(rawPrivateKey: Data([0x00, 0x01, 0x02]))
        }
    }

    @Test("X25519 agreement is symmetric between two devices")
    func agreementSymmetry() throws {
        let a = DeviceKeypair()
        let b = DeviceKeypair()
        let ab = try a.sharedSecret(withPeerPublicKey: b.publicKeyRaw)
        let ba = try b.sharedSecret(withPeerPublicKey: a.publicKeyRaw)
        // SharedSecret isn't directly comparable; derive a key from each and
        // compare the bytes — that's what the session layer actually does.
        func derived(_ s: SharedSecret) -> Data {
            s.hkdfDerivedSymmetricKey(using: SHA256.self, salt: Data(), sharedInfo: Data(), outputByteCount: 32)
                .withUnsafeBytes { Data($0) }
        }
        #expect(derived(ab) == derived(ba))
    }
}
