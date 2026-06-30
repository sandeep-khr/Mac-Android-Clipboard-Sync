import Foundation

/// Shared protocol constants. Keep in sync with `docs/protocol.md`.
public enum ClipSyncProtocol {
    /// Bonjour / NSD service type both sides agree on.
    public static let serviceType = "_clipsync._tcp"

    /// Wire protocol version, exchanged in `hello` and the Bonjour TXT record.
    public static let version = 1
}

/// Identifies one device (this Mac) on the network. The id is stable across
/// launches; the name is human-readable for the pairing/discovery UI.
public struct DeviceIdentity {
    public let id: String
    public let name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }

    /// The Bonjour TXT record advertised alongside the service, per
    /// `docs/protocol.md` (§ Discovery).
    public func txtRecord() -> [String: String] {
        [
            "device_name": name,
            "device_id": id,
            "protocol_version": String(ClipSyncProtocol.version),
        ]
    }
}
