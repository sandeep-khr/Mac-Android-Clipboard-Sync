import Foundation
import Testing
@testable import ClipSyncCore

@Suite("AppState menu display model")
struct AppStateTests {

    private func event(_ text: String) -> ClipboardEvent {
        ClipboardEvent(
            id: UUID(),
            timestamp: Date(timeIntervalSince1970: 0),
            text: text,
            normalizedText: text,
            hash: ClipboardNormalizer.hash(text)
        )
    }

    @Test("starts with zero events and no preview")
    func initialState() {
        let state = AppState()
        #expect(state.eventsSynced == 0)
        #expect(state.lastPreview == nil)
    }

    @Test("recording an event increments the count and sets the preview")
    func recordsOneEvent() {
        let state = AppState()
        state.recordSyncedEvent(event("hello"))
        #expect(state.eventsSynced == 1)
        #expect(state.lastPreview == "hello")
    }

    @Test("the preview reflects the most recent event")
    func previewIsLatest() {
        let state = AppState()
        state.recordSyncedEvent(event("first"))
        state.recordSyncedEvent(event("second"))
        #expect(state.eventsSynced == 2)
        #expect(state.lastPreview == "second")
    }

    @Test("a long preview is truncated with an ellipsis")
    func truncatesLongPreview() {
        let state = AppState(previewLimit: 10)
        state.recordSyncedEvent(event("0123456789ABCDEF"))
        #expect(state.lastPreview == "0123456789…")
    }

    @Test("newlines in the preview are collapsed to spaces for single-line display")
    func collapsesNewlines() {
        let state = AppState()
        state.recordSyncedEvent(event("line1\nline2"))
        #expect(state.lastPreview == "line1 line2")
    }
}
