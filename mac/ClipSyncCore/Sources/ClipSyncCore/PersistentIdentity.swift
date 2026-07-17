import Foundation

/// Loads — or on first run creates and persists — this device's stable id and
/// X25519 identity keypair, through a `KeyStore` (see `docs/pairing-flow.md`).
///
/// This is the durable replacement for the throwaway per-launch `UUID()` the
/// menu bar app currently uses: the device id and private key must survive
/// relaunches so a paired peer keeps recognizing us.
public struct PersistentIdentity {
    static let deviceIdKey = "identity.deviceId"
    static let privateKeyKey = "identity.privateKey"

    private let keyStore: KeyStore

    public init(keyStore: KeyStore) {
        self.keyStore = keyStore
    }

    public struct Loaded {
        public let deviceId: String
        public let keypair: DeviceKeypair
    }

    /// Idempotent: the first call generates and persists a new identity; every
    /// later call returns the same id and keypair.
    public func loadOrCreate() throws -> Loaded {
        if let idData = try keyStore.data(forKey: Self.deviceIdKey),
           let deviceId = String(data: idData, encoding: .utf8),
           let keyData = try keyStore.data(forKey: Self.privateKeyKey) {
            return Loaded(deviceId: deviceId, keypair: try DeviceKeypair(rawPrivateKey: keyData))
        }

        let deviceId = UUID().uuidString
        let keypair = DeviceKeypair()
        try keyStore.set(Data(deviceId.utf8), forKey: Self.deviceIdKey)
        try keyStore.set(keypair.privateKeyRaw, forKey: Self.privateKeyKey)
        return Loaded(deviceId: deviceId, keypair: keypair)
    }
}
