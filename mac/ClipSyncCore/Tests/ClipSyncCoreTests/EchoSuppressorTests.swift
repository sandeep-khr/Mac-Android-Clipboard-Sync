import Foundation
import Testing
@testable import ClipSyncCore

@Suite("EchoSuppressor — bidirectional loop prevention")
struct EchoSuppressorTests {

    @Test("suppresses a just-applied hash exactly once")
    func suppressesOnce() {
        let s = EchoSuppressor()
        s.markApplied("h1")
        #expect(s.shouldSuppress("h1") == true)   // the immediate echo from the watcher
        #expect(s.shouldSuppress("h1") == false)  // a later genuine local re-copy still syncs
    }

    @Test("does not suppress content we never applied")
    func ignoresUnrelated() {
        let s = EchoSuppressor()
        s.markApplied("h1")
        #expect(s.shouldSuppress("h2") == false)
    }

    @Test("bounded — oldest records are evicted")
    func bounded() {
        let s = EchoSuppressor(limit: 2)
        s.markApplied("a")
        s.markApplied("b")
        s.markApplied("c") // evicts "a"
        #expect(s.shouldSuppress("a") == false)
        #expect(s.shouldSuppress("b") == true)
        #expect(s.shouldSuppress("c") == true)
    }
}
