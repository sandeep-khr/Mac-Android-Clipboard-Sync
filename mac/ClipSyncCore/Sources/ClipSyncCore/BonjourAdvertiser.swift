import Foundation
import Network

/// Advertises this Mac on the local network as a `_clipsync._tcp` service so the
/// Android app can discover it without knowing an IP address (see
/// `docs/protocol.md` § Discovery).
///
/// Phase 2 only opens the listener and publishes the Bonjour service; incoming
/// connections are refused. Phase 3 will accept them and upgrade to WebSocket.
public final class BonjourAdvertiser {
    private let identity: DeviceIdentity
    private let desiredPort: NWEndpoint.Port
    private let queue = DispatchQueue(label: "com.clipsync.bonjour")
    private var listener: NWListener?

    /// - Parameter port: fixed port to listen on, or `nil` to let the OS assign
    ///   one (advertised via Bonjour so the client still finds it).
    public init(identity: DeviceIdentity, port: UInt16? = nil) {
        self.identity = identity
        self.desiredPort = port.flatMap { NWEndpoint.Port(rawValue: $0) } ?? .any
    }

    public func start() throws {
        let listener = try NWListener(using: .tcp, on: desiredPort)

        var txt = NWTXTRecord()
        for (key, value) in identity.txtRecord() {
            txt[key] = value
        }
        listener.service = NWListener.Service(
            name: identity.name,
            type: ClipSyncProtocol.serviceType,
            txtRecord: txt
        )

        listener.newConnectionHandler = { connection in
            // Phase 3 will accept and upgrade to WebSocket. For now, refuse.
            connection.cancel()
        }

        listener.start(queue: queue)
        self.listener = listener
    }

    public func stop() {
        listener?.cancel()
        listener = nil
    }
}
