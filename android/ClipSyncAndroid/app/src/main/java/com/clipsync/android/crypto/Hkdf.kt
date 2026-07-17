package com.clipsync.android.crypto

import org.bouncycastle.crypto.digests.SHA256Digest
import org.bouncycastle.crypto.generators.HKDFBytesGenerator
import org.bouncycastle.crypto.params.HKDFParameters

/**
 * HKDF-SHA256, matching CryptoKit's `HKDF<SHA256>`. An empty salt is treated as
 * HashLen zero bytes (RFC 5869) — which is what CryptoKit's empty-salt HMAC
 * reduces to, so both platforms derive identical keys.
 */
object Hkdf {
    fun derive(ikm: ByteArray, salt: ByteArray, info: ByteArray, length: Int): ByteArray {
        val generator = HKDFBytesGenerator(SHA256Digest())
        generator.init(HKDFParameters(ikm, salt, info))
        val out = ByteArray(length)
        generator.generateBytes(out, 0, length)
        return out
    }
}
