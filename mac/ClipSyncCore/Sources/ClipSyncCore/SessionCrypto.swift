import Foundation
import CryptoKit

/// Per-connection authenticated encryption for `clipboard_update` payloads
/// (see `docs/pairing-flow.md` § Session keys).
///
/// The session key is derived from the two devices' long-term identity keys:
/// `sessionKey = HKDF-SHA256(X25519(ourPrivate, theirPublic), info:"clipsync-session-v1")`.
/// Both peers derive the identical key, so either can `seal` and the other can
/// `open`. Payloads are sealed with **AES-256-GCM** and a fresh 96-bit nonce per
/// message.
///
/// The byte encoding here (raw 32-byte keys, empty salt, this info string, and
/// the `ciphertext‖tag` wire layout) is the cross-platform contract the Android
/// app must match exactly.
public struct SessionCrypto {
    /// HKDF `info` binding the derivation to this protocol + version.
    static let info = Data("clipsync-session-v1".utf8)

    private let key: SymmetricKey

    /// Derives the session key from our keypair and the peer's raw public key.
    public init(ourKeypair: DeviceKeypair, peerPublicKey: Data) throws {
        let shared = try ourKeypair.sharedSecret(withPeerPublicKey: peerPublicKey)
        self.key = shared.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: Data(),
            sharedInfo: SessionCrypto.info,
            outputByteCount: 32
        )
    }

    /// The raw 32-byte session key. Internal — for tests / diagnostics only.
    var keyData: Data { key.withUnsafeBytes { Data($0) } }

    /// Encrypts UTF-8 text → base64 `nonce` and base64 `ciphertext‖tag`, the two
    /// fields carried in the encrypted `clipboard_update`.
    public func seal(_ text: String) throws -> (nonce: String, ciphertext: String) {
        let box = try AES.GCM.seal(Data(text.utf8), using: key)
        let nonce = Data(box.nonce)
        let ciphertextAndTag = box.ciphertext + box.tag
        return (nonce.base64EncodedString(), ciphertextAndTag.base64EncodedString())
    }

    /// Decrypts a `nonce` / `ciphertext‖tag` pair back to text. Throws if the
    /// input is malformed or the GCM tag fails (tampering / wrong key).
    public func open(nonce: String, ciphertext: String) throws -> String {
        guard let nonceData = Data(base64Encoded: nonce),
              let combined = Data(base64Encoded: ciphertext),
              combined.count >= 16
        else {
            throw CryptoError.malformed
        }
        let ct = combined.prefix(combined.count - 16)
        let tag = combined.suffix(16)
        let box = try AES.GCM.SealedBox(
            nonce: try AES.GCM.Nonce(data: nonceData),
            ciphertext: ct,
            tag: tag
        )
        let plaintext = try AES.GCM.open(box, using: key)
        guard let text = String(data: plaintext, encoding: .utf8) else {
            throw CryptoError.invalidUTF8
        }
        return text
    }

    public enum CryptoError: Error { case malformed, invalidUTF8 }
}
