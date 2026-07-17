package com.clipsync.android.crypto

/**
 * Short Authentication String — the 6-digit pairing code, matching the Mac
 * `SASCode`. Both devices sort the two raw public keys, concatenate, then
 * HKDF-SHA256 (info "clipsync-sas") to 4 bytes read big-endian, mod 1_000_000.
 */
object SasCode {

    fun derive(keyA: ByteArray, keyB: ByteArray): String {
        val sorted = if (lexicographicallyPrecedes(keyA, keyB)) keyA + keyB else keyB + keyA
        val derived = Hkdf.derive(
            ikm = sorted,
            salt = ByteArray(0),
            info = "clipsync-sas".toByteArray(Charsets.UTF_8),
            length = 4,
        )
        var value = 0L
        for (b in derived) value = (value shl 8) or (b.toLong() and 0xff)
        return (value % 1_000_000L).toString().padStart(6, '0')
    }

    private fun lexicographicallyPrecedes(a: ByteArray, b: ByteArray): Boolean {
        val n = minOf(a.size, b.size)
        for (i in 0 until n) {
            val ai = a[i].toInt() and 0xff
            val bi = b[i].toInt() and 0xff
            if (ai != bi) return ai < bi
        }
        return a.size < b.size
    }
}
