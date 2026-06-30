import Foundation

/// Display model for the menu bar app. Tracks how many clipboard events have
/// been handled and a short, single-line preview of the most recent one.
///
/// Kept in `ClipSyncCore` (not the app target) so it is unit-testable without
/// AppKit. Mutate it on the main thread; the menu reads from it directly.
public final class AppState {
    public private(set) var eventsSynced: Int = 0
    public private(set) var lastPreview: String?

    private let previewLimit: Int

    public init(previewLimit: Int = 40) {
        self.previewLimit = max(1, previewLimit)
    }

    /// Records that a clipboard event was handled, updating the count and the
    /// single-line preview shown in the menu.
    public func recordSyncedEvent(_ event: ClipboardEvent) {
        eventsSynced += 1
        lastPreview = Self.previewText(event.normalizedText, limit: previewLimit)
    }

    /// Collapses newlines to spaces and truncates to `limit` characters,
    /// appending an ellipsis when the text was shortened.
    static func previewText(_ text: String, limit: Int) -> String {
        let singleLine = text
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")

        guard singleLine.count > limit else {
            return singleLine
        }
        return String(singleLine.prefix(limit)) + "…"
    }
}
