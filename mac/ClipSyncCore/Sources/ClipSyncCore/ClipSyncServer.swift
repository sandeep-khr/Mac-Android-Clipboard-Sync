import Foundation
import Network

/// The Mac-side server: advertises `_clipsync._tcp` over Bonjour *and* accepts
/// WebSocket connections. Per connection it performs the `hello` handshake
/// (exchange public keys → derive a session key), then broadcasts **encrypted**
/// `clipboard_update` messages to every handshaken client (see `docs/protocol.md`
/// and `docs/pairing-flow.md`).
///
/// Each connection has its own session key, so a clipboard event is sealed
/// separately per client. Identity keys are ephemeral for now (regenerated per
/// launch); persistent identity + the SAS match gate are the next step, and the
/// derived SAS is already logged here for that UI.
///
/// Thread-safety: all mutable state is touched only on `queue`; public methods
/// hop onto it. Hence `@unchecked Sendable`.
public final class ClipSyncServer: @unchecked Sendable {
    private let identity: DeviceIdentity
    private let keypair: DeviceKeypair
    private let queue = DispatchQueue(label: "com.clipsync.server")
    private var listener: NWListener?
    private var clients: [ObjectIdentifier: ClientConnection] = [:]

    /// Called on `queue` when a peer sends us a clipboard update (the Android→Mac
    /// direction). The app applies the decrypted text to `NSPasteboard`.
    public var onRemoteClipboard: (@Sendable (String) -> Void)?

    /// Called on `queue` after a peer completes the handshake (with its name), and
    /// when a peer disconnects — for the menu's "connected device" line.
    public var onPeerConnected: (@Sendable (String) -> Void)?
    public var onPeerDisconnected: (@Sendable () -> Void)?

    public init(identity: DeviceIdentity, keypair: DeviceKeypair) {
        self.identity = identity
        self.keypair = keypair
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
            self.clients.values.forEach { $0.connection.cancel() }
            self.clients.removeAll()
            self.listener?.cancel()
            self.listener = nil
        }
    }

    // MARK: - Broadcasting

    /// Seals `event` under each handshaken client's session key and sends it as an
    /// encrypted `clipboard_update` text frame.
    public func broadcast(event: ClipboardEvent) {
        queue.async { [weak self] in
            guard let self else { return }
            for client in self.clients.values {
                guard let session = client.session else { continue } // not handshaken yet
                do {
                    let message = try EncryptedClipboardUpdate(
                        event: event,
                        origin: self.identity.id,
                        session: session
                    )
                    self.send(try message.jsonData(), on: client.connection)
                } catch {
                    self.log("failed to seal clipboard_update: \(error)")
                }
            }
        }
    }

    // MARK: - Connections (all on `queue`)

    private func accept(_ connection: NWConnection) {
        let client = ClientConnection(connection: connection)
        clients[ObjectIdentifier(connection)] = client
        log("client connected (\(clients.count) total); sending hello")

        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .cancelled, .failed:
                self?.remove(connection)
            default:
                break
            }
        }
        receive(on: client)
        connection.start(queue: queue)

        // Send our hello as soon as the socket is up.
        let hello = HelloMessage(
            deviceId: identity.id,
            deviceName: identity.name,
            publicKey: keypair.publicKeyBase64
        )
        if let data = try? hello.jsonData() {
            send(data, on: connection)
        }
    }

    private func remove(_ connection: NWConnection) {
        let hadSession = clients[ObjectIdentifier(connection)]?.session != nil
        clients[ObjectIdentifier(connection)] = nil
        log("client disconnected (\(clients.count) total)")
        if hadSession { onPeerDisconnected?() }
    }

    /// Reads one WebSocket message at a time and re-arms. The only inbound message
    /// we act on today is the peer's `hello`; `ack`/others are ignored for now.
    private func receive(on client: ClientConnection) {
        client.connection.receiveMessage { [weak self] content, _, _, error in
            guard let self else { return }
            if let content, !content.isEmpty {
                self.handleInbound(content, from: client)
            }
            guard error == nil else { return }
            self.receive(on: client)
        }
    }

    private func handleInbound(_ data: Data, from client: ClientConnection) {
        // Handshake first: derive the session key from the peer's hello.
        if client.session == nil {
            guard let hello = try? HelloMessage.decode(data), hello.type == "hello",
                  let peerPublicKey = Data(base64Encoded: hello.publicKey) else { return }
            do {
                client.session = try SessionCrypto(ourKeypair: keypair, peerPublicKey: peerPublicKey)
                client.peerDeviceId = hello.deviceId
                let sas = SASCode.derive(keypair.publicKeyRaw, peerPublicKey)
                log("handshake complete with \(hello.deviceName) [\(hello.deviceId.prefix(8))] — SAS \(sas)")
                onPeerConnected?(hello.deviceName)
            } catch {
                log("handshake failed: \(error)")
            }
            return
        }

        // Encrypted clipboard update from the peer (Android → Mac).
        guard let session = client.session,
              let update = try? JSONDecoder().decode(EncryptedClipboardUpdate.self, from: data),
              update.type == "clipboard_update" else { return }
        do {
            let text = try session.open(nonce: update.nonce, ciphertext: update.ciphertext)
            onRemoteClipboard?(text)
        } catch {
            log("failed to open inbound clipboard_update: \(error)")
        }
    }

    /// Sends `data` as a WebSocket text frame.
    private func send(_ data: Data, on connection: NWConnection) {
        let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.ContentContext(identifier: "clipsync", metadata: [metadata])
        connection.send(content: data, contentContext: context, completion: .contentProcessed { _ in })
    }

    /// Opt-in diagnostics to stderr (`CLIPSYNC_DEBUG=1`). Never logs clipboard
    /// contents.
    private func log(_ message: String) {
        guard ProcessInfo.processInfo.environment["CLIPSYNC_DEBUG"] == "1" else { return }
        FileHandle.standardError.write(Data("[clipsync-server] \(message)\n".utf8))
    }
}

/// Per-connection state: the socket plus, once the `hello` handshake completes,
/// the session key used to encrypt this client's clipboard updates.
///
/// Only ever touched on `ClipSyncServer.queue`, hence `@unchecked Sendable`.
final class ClientConnection: @unchecked Sendable {
    let connection: NWConnection
    var session: SessionCrypto?
    var peerDeviceId: String?

    init(connection: NWConnection) {
        self.connection = connection
    }
}
