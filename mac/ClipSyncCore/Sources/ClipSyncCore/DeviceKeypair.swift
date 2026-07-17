import Foundation
import CryptoKit

/// This device's long-term **X25519** identity keypair (see `docs/pairing-flow.md`).
///
/// Wraps CryptoKit's `Curve25519.KeyAgreement` keys and exposes the raw 32-byte
/// representations that travel in `hello` (public key) and get persisted in the
/// Keychain (private key). The keypair is symmetric per device, which is what
/// lets sync become bidirectional later without a protocol change.
public struct DeviceKeypair {
    public let privateKey: Curve25519.KeyAgreement.PrivateKey

    /// Generates a fresh keypair (first run).
    public init() {
        self.privateKey = Curve25519.KeyAgreement.PrivateKey()
    }

    /// Rehydrates a keypair from a stored 32-byte raw private key.
    public init(rawPrivateKey: Data) throws {
        self.privateKey = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: rawPrivateKey)
    }

    /// 32-byte raw private key — persist this (Keychain); never send it.
    public var privateKeyRaw: Data { privateKey.rawRepresentation }

    /// 32-byte raw public key — safe to share; travels in `hello`.
    public var publicKeyRaw: Data { privateKey.publicKey.rawRepresentation }

    /// The public key in the exact base64 form carried on the wire.
    public var publicKeyBase64: String { publicKeyRaw.base64EncodedString() }

    /// X25519 key agreement with a peer's raw 32-byte public key.
    public func sharedSecret(withPeerPublicKey peerPublicKey: Data) throws -> SharedSecret {
        let peer = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: peerPublicKey)
        return try privateKey.sharedSecretFromKeyAgreement(with: peer)
    }
}
