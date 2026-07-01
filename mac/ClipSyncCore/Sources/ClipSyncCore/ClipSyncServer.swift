import Foundation
import Network

/// The Mac-side server: advertises `_clipsync._tcp` over Bonjour *and* accepts
/// WebSocket connections, then broadcasts `clipboard_update` messages to every
/// connected client (see `docs/protocol.md`).
///
/// This supersedes the Phase 2 advertise-only `BonjourAdvertiser`: one
/// `NWListener` both publishes the service and serves WebSocket, so the port it
/// advertises is the port clients connect to.
///
/// Thread-safety: all mutable state is touched only on `queue`; public methods
/// hop onto it. Hence `@unchecked Sendable`.
public final class ClipSyncServer: @unchecked Sendable {
    private let identity: DeviceIdentity
    private let queue = DispatchQueue(label: "com.clipsync.server")
    private var listener: NWListener?
    private var connections: [NWConnection] = []

    public init(identity: DeviceIdentity) {
        self.identity = identity
    }

    // MARK: - Lifecycle

    public func start() throws {
        let parameters = NWParameters.tcp
        let webSocket = NWProtocolWebSocket.Options()
        webSocket.autoReplyPing = true
        parameters.defaultProtocolStack.applicationProtocols.insert(webSocket, at: 0)

        let listener = try NWListener(using: parameters) // OS-assigned port

        var txt = NWTXTRecord()
        for (key, value) in identity.txtRecord() {
            txt[key] = value
        }
        listener.service = NWListener.Service(
            name: identity.name,
            type: ClipSyncProtocol.serviceType,
            txtRecord: txt
        )

        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }
        listener.start(queue: queue)
        self.listener = listener
    }

    public func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            self.connections.forEach { $0.cancel() }
            self.connections.removeAll()
            self.listener?.cancel()
            self.listener = nil
        }
    }

    // MARK: - Broadcasting

    /// Sends `data` as a WebSocket text frame to every connected client.
    public func broadcast(_ data: Data) {
        queue.async { [weak self] in
            guard let self else { return }
            let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
            let context = NWConnection.ContentContext(identifier: "clipboard", metadata: [metadata])
            for connection in self.connections {
                connection.send(
                    content: data,
                    contentContext: context,
                    completion: .contentProcessed { _ in }
                )
            }
        }
    }

    // MARK: - Connections (all on `queue`)

    private func accept(_ connection: NWConnection) {
        connections.append(connection)
        log("client connected (\(connections.count) total)")

        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .cancelled, .failed:
                self?.remove(connection)
            default:
                break
            }
        }
        receive(on: connection)
        connection.start(queue: queue)
    }

    private func remove(_ connection: NWConnection) {
        connections.removeAll { $0 === connection }
        log("client disconnected (\(connections.count) total)")
    }

    /// Drains incoming frames (acks/hello). Phase 3 doesn't act on them yet, but
    /// we must keep reading so the connection stays healthy.
    private func receive(on connection: NWConnection) {
        connection.receiveMessage { [weak self] _, _, _, error in
            guard error == nil else { return }
            self?.receive(on: connection)
        }
    }

    /// Opt-in diagnostics to stderr (`CLIPSYNC_DEBUG=1`). Never logs clipboard
    /// contents.
    private func log(_ message: String) {
        guard ProcessInfo.processInfo.environment["CLIPSYNC_DEBUG"] == "1" else { return }
        FileHandle.standardError.write(Data("[clipsync-server] \(message)\n".utf8))
    }
}
