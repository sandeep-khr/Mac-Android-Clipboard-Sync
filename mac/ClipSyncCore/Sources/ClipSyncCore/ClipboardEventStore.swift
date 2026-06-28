import Foundation

/// Tracks recently seen content hashes so the same clipboard content is not
/// sent repeatedly. This is the sender-side half of duplicate suppression
/// described in `docs/protocol.md`.
public final class ClipboardEventStore {
    private let historyLimit: Int
    private var recentHashes: [String] = []

    public init(historyLimit: Int = 16) {
        self.historyLimit = max(1, historyLimit)
    }

    /// Records `hash` as just-seen. Returns `true` if it was not in recent
    /// history (caller should send), or `false` if it is a recent duplicate
    /// (caller should suppress).
    public func registerIfNew(hash: String) -> Bool {
        if recentHashes.contains(hash) {
            return false
        }

        recentHashes.append(hash)
        if recentHashes.count > historyLimit {
            recentHashes.removeFirst(recentHashes.count - historyLimit)
        }
        return true
    }
}
