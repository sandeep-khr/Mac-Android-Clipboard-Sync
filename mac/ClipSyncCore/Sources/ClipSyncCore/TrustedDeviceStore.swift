import Foundation

/// Remembers the peers we've paired with: peer device id → peer's raw public key
/// (see `docs/pairing-flow.md`). Backed by a `KeyStore` so it persists in the
/// Keychain and is testable in memory.
///
/// A device present here is trusted, so reconnection is silent (no re-pairing).
/// `untrust` removes it, forcing a fresh SAS/QR pairing next time — the "unpair"
/// action.
public struct TrustedDeviceStore {
    static let prefix = "trusted."

    private let keyStore: KeyStore

    public init(keyStore: KeyStore) {
        self.keyStore = keyStore
    }

    /// Stores (or updates) a trusted peer's public key.
    public func trust(deviceId: String, publicKey: Data) throws {
        try keyStore.set(publicKey, forKey: Self.prefix + deviceId)
    }

    /// The trusted peer's raw public key, or `nil` if not paired.
    public func publicKey(forDeviceId deviceId: String) throws -> Data? {
        try keyStore.data(forKey: Self.prefix + deviceId)
    }

    public func isTrusted(deviceId: String) throws -> Bool {
        try publicKey(forDeviceId: deviceId) != nil
    }

    /// Removes a peer (unpair).
    public func untrust(deviceId: String) throws {
        try keyStore.remove(forKey: Self.prefix + deviceId)
    }
}
