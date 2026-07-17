import Foundation
import Testing
@testable import ClipSyncCore

@Suite("SASCode — 6-digit pairing code")
struct SASCodeTests {

    /// Two fixed 32-byte public keys used as a cross-platform test vector.
    private let keyA = Data((0..<32).map { UInt8($0) })          // 00 01 … 1f
    private let keyB = Data((0..<32).map { UInt8(255 - $0) })    // ff fe … e0

    @Test("code is exactly 6 decimal digits")
    func sixDigits() {
        let code = SASCode.derive(DeviceKeypair().publicKeyRaw, DeviceKeypair().publicKeyRaw)
        let allDigits = code.allSatisfy { $0.isNumber }
        #expect(code.count == 6)
        #expect(allDigits)
    }

    @Test("order-independent: both devices compute the same code")
    func orderIndependent() {
        #expect(SASCode.derive(keyA, keyB) == SASCode.derive(keyB, keyA))
    }

    @Test("known-answer vector is stable (the contract with Android)")
    func knownAnswer() {
        // This literal pins the exact derivation. If it ever changes, the Android
        // SAS implementation must be updated to match (and vice-versa).
        #expect(SASCode.derive(keyA, keyB) == "064987")
    }
}
