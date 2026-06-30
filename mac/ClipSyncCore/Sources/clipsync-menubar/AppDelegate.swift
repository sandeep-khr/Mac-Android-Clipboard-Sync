import AppKit
import ClipSyncCore

/// Menu bar controller for ClipSync.
///
/// This is the thin AppKit shell: it owns the status item + menu and forwards
/// clipboard events from `PasteboardWatcher` into the testable `AppState`,
/// then refreshes the menu titles. All non-UI logic lives in `ClipSyncCore`.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let state = AppState()
    private var watcher: PasteboardWatcher?

    private var statusItem: NSStatusItem?
    private let countItem = NSMenuItem(title: "Events synced: 0", action: nil, keyEquivalent: "")
    private let lastItem = NSMenuItem(title: "Last: —", action: nil, keyEquivalent: "")

    func applicationDidFinishLaunching(_ notification: Notification) {
        setUpStatusItem()
        startWatching()
    }

    // MARK: - Menu bar

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(
            systemSymbolName: "clipboard",
            accessibilityDescription: "ClipSync"
        )
        item.menu = makeMenu()
        statusItem = item
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()

        let header = NSMenuItem(title: "ClipSync — watching clipboard", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        menu.addItem(.separator())

        countItem.isEnabled = false
        menu.addItem(countItem)

        lastItem.isEnabled = false
        menu.addItem(lastItem)

        menu.addItem(.separator())

        // Placeholder for Phase 2+ (discovery / pairing).
        let devices = NSMenuItem(title: "Devices…", action: nil, keyEquivalent: "")
        devices.isEnabled = false
        menu.addItem(devices)

        menu.addItem(.separator())

        let quit = NSMenuItem(
            title: "Quit ClipSync",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        menu.addItem(quit)

        return menu
    }

    // MARK: - Clipboard watching

    private func startWatching() {
        let watcher = PasteboardWatcher { [weak self] event in
            self?.handle(event)
        }
        watcher.start()
        self.watcher = watcher
    }

    private func handle(_ event: ClipboardEvent) {
        state.recordSyncedEvent(event)
        countItem.title = "Events synced: \(state.eventsSynced)"
        lastItem.title = "Last: \(state.lastPreview ?? "—")"
        log("event #\(state.eventsSynced) hash=\(event.hash.prefix(8)) preview=\(state.lastPreview ?? "")")
    }

    /// Opt-in diagnostic logging to stderr. Enable with `CLIPSYNC_DEBUG=1`.
    /// Never logs full clipboard contents above this short preview.
    private func log(_ message: String) {
        guard ProcessInfo.processInfo.environment["CLIPSYNC_DEBUG"] == "1" else { return }
        FileHandle.standardError.write(Data("[clipsync] \(message)\n".utf8))
    }
}
