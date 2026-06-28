import Testing
@testable import ClipSyncCore

@Suite("ClipboardNormalizer")
struct ClipboardNormalizerTests {

    @Test("converts CRLF line endings to LF")
    func normalizesCRLF() {
        #expect(ClipboardNormalizer.normalize("a\r\nb") == "a\nb")
    }

    @Test("converts lone CR to LF")
    func normalizesCR() {
        #expect(ClipboardNormalizer.normalize("a\rb") == "a\nb")
    }

    @Test("trims surrounding whitespace and newlines")
    func trimsOuterWhitespace() {
        #expect(ClipboardNormalizer.normalize("  hello \n") == "hello")
    }

    @Test("preserves internal whitespace")
    func preservesInternalWhitespace() {
        #expect(ClipboardNormalizer.normalize("a  b") == "a  b")
    }

    @Test("identical normalized input produces identical hashes")
    func hashIsStable() {
        let a = ClipboardNormalizer.hash("hello")
        let b = ClipboardNormalizer.hash("hello")
        #expect(a == b)
    }

    @Test("different input produces different hashes")
    func hashDiffersByInput() {
        #expect(ClipboardNormalizer.hash("hello") != ClipboardNormalizer.hash("world"))
    }

    @Test("hash is lowercase 64-character SHA-256 hex")
    func hashFormat() {
        let h = ClipboardNormalizer.hash("anything")
        #expect(h.count == 64)
        #expect(h == h.lowercased())
        #expect(h.allSatisfy { $0.isHexDigit })
    }
}
