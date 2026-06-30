import AppKit
import Foundation

@MainActor
public final class PasteboardWatcher {
    private let pasteboard: NSPasteboard
    private let pollInterval: TimeInterval
    private var lastChangeCount: Int
    private let eventStore = ClipboardEventStore()
    private var timer: Timer?
    private let onEvent: (ClipboardEvent) -> Void

    public init(
        pasteboard: NSPasteboard = .general,
        pollInterval: TimeInterval = 0.4,
        onEvent: @escaping (ClipboardEvent) -> Void
    ) {
        self.pasteboard = pasteboard
        self.pollInterval = pollInterval
        self.lastChangeCount = pasteboard.changeCount
        self.onEvent = onEvent
    }

    public func start() {
        let timer = Timer(timeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.poll()
            }
        }

        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func poll() {
        guard pasteboard.changeCount != lastChangeCount else {
            return
        }

        lastChangeCount = pasteboard.changeCount

        guard let rawText = pasteboard.string(forType: .string) else {
            return
        }

        let normalizedText = ClipboardNormalizer.normalize(rawText)
        guard normalizedText.isEmpty == false else {
            return
        }

        let hash = ClipboardNormalizer.hash(normalizedText)
        guard eventStore.registerIfNew(hash: hash) else {
            return
        }

        onEvent(
            ClipboardEvent(
                id: UUID(),
                timestamp: Date(),
                text: rawText,
                normalizedText: normalizedText,
                hash: hash
            )
        )
    }
}
