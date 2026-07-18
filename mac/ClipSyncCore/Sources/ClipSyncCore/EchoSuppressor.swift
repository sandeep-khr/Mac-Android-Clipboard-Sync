import Foundation

/// Prevents A→B→A clipboard loops once sync is bidirectional.
///
/// When we apply a clipboard update *received from a peer*, the local pasteboard
/// watcher immediately fires for that same content — which would re-broadcast it
/// straight back. We record the applied content hash here and suppress exactly
/// that one echo. The record is consumed on suppression, so if the user later
/// genuinely copies the same text again, it still syncs.
public final class EchoSuppressor: @unchecked Sendable {
    private var hashes: [String] = []
    private let limit: Int
    private let lock = NSLock()

    public init(limit: Int = 16) {
        self.limit = limit
    }

    /// Record that `hash` was just applied from a remote peer.
    public func markApplied(_ hash: String) {
        lock.lock(); defer { lock.unlock() }
        hashes.append(hash)
        if hashes.count > limit {
            hashes.removeFirst(hashes.count - limit)
        }
    }

    /// Returns `true` (and consumes the record) if `hash` was applied from a
    /// remote peer and should therefore NOT be re-broadcast.
    public func shouldSuppress(_ hash: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard let index = hashes.firstIndex(of: hash) else { return false }
        hashes.remove(at: index)
        return true
    }
}
