import Testing
@testable import ClipSyncCore

@Suite("ClipboardEventStore dedupe")
struct ClipboardEventStoreTests {

    @Test("a never-before-seen hash is new")
    func firstHashIsNew() {
        let store = ClipboardEventStore()
        #expect(store.registerIfNew(hash: "abc") == true)
    }

    @Test("the same hash repeated immediately is suppressed")
    func repeatedHashSuppressed() {
        let store = ClipboardEventStore()
        _ = store.registerIfNew(hash: "abc")
        #expect(store.registerIfNew(hash: "abc") == false)
    }

    @Test("a different hash is new even after another was registered")
    func differentHashIsNew() {
        let store = ClipboardEventStore()
        _ = store.registerIfNew(hash: "abc")
        #expect(store.registerIfNew(hash: "def") == true)
    }

    @Test("a recent hash stays suppressed while within the history window")
    func recentHashStaysSuppressed() {
        let store = ClipboardEventStore(historyLimit: 8)
        _ = store.registerIfNew(hash: "abc")
        _ = store.registerIfNew(hash: "def")
        // "abc" is still in recent history, so it must remain suppressed
        #expect(store.registerIfNew(hash: "abc") == false)
    }

    @Test("a hash evicted past the history limit is treated as new again")
    func evictedHashIsNewAgain() {
        let store = ClipboardEventStore(historyLimit: 2)
        _ = store.registerIfNew(hash: "first")
        _ = store.registerIfNew(hash: "second")
        _ = store.registerIfNew(hash: "third") // evicts "first"
        #expect(store.registerIfNew(hash: "first") == true)
    }
}
