import Foundation
import CryptoKit

/// Short Authentication String — the 6-digit code both devices derive from their
/// two public keys and show to the user during first-time pairing
/// (see `docs/pairing-flow.md`). If the codes match, there is no
/// man-in-the-middle and the keys are authentic.
///
/// Both devices MUST derive the identical code, so the byte encoding below is the
/// cross-platform contract with the Android app:
///
/// 1. Sort the two raw 32-byte public keys by their bytes (so order doesn't
///    matter) and concatenate → a 64-byte transcript.
/// 2. `HKDF-SHA256(ikm: transcript, salt: empty, info: "clipsync-sas", L: 4)`.
/// 3. Read the 4 output bytes as a big-endian `UInt32`, take it `mod 1_000_000`,
///    zero-pad to 6 digits.
public enum SASCode {
    /// HKDF `info` binding the derivation to the SAS purpose.
    static let info = Data("clipsync-sas".utf8)

    /// Derives the 6-digit code from two raw 32-byte X25519 public keys.
    /// Order-independent by construction.
    public static func derive(_ keyA: Data, _ keyB: Data) -> String {
        let sorted = keyA.lexicographicallyPrecedes(keyB) ? [keyA, keyB] : [keyB, keyA]
        var transcript = Data()
        transcript.append(sorted[0])
        transcript.append(sorted[1])

        let derived = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: transcript),
            salt: Data(),
            info: info,
            outputByteCount: 4
        )
        let bytes = derived.withUnsafeBytes { Data($0) }
        let value = bytes.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        return String(format: "%06u", value % 1_000_000)
    }
}
